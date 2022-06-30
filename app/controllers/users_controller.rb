require 'tzinfo'

class UsersController < ApplicationController
  layout "login_signup"
  before_action :authorize, except: [:new, :create]

  def new
    @user = User.new
    render "signup_login/signup"
  end

  def create
    user_params = params.permit(:email, "new-password", :timezone, :time_offset)
    User.transaction do
      existing_user = User.find_by(email: user_params["email"])
      if existing_user && existing_user.password_digest.nil?
        @user = existing_user
        @user.password = user_params["new-password"]
      else
        @user = User.new({ email: user_params["email"], password: user_params["new-password"] })

        Rails.logger.info("Timezone in: #{user_params["timezone"]}, offset in: #{user_params["time_offset"]}")
        if TimezoneHelper::TZINFO_ALL_TIMEZONES.include?(user_params["timezone"])
          @timezone = user_params["timezone"]
        else
          Rails.logger.warn("Unknown timezone: #{user_params["timezone"]}")
          offset_hours_inverted = (user_params["time_offset"].to_f / 60).round
          if -14 <= offset_hours_inverted && offset_hours_inverted <= 12
            offset_str = offset_hours_inverted >= 0 ? "+#{offset_hours_inverted}" : offset_hours_inverted.to_s
            @timezone = "Etc/GMT#{offset_str}"
          else
            @timezone = "UTC"
          end
        end
        Rails.logger.info("Timezone out: #{@timezone}")
      end

      if @user.save
        unless existing_user
          UserSettings.create!(
            user_id: @user.id, timezone: @timezone, delivery_channel: "multiple_feeds", version: 1
          )
          UpdateRssJob.initial_schedule(@user)
          EmailPostsJob.initial_schedule(@user)
        end

        session[:user_id] = @user.id

        if cookies[:anonymous_subscription]
          subscription = Subscription.find_by(id: cookies[:anonymous_subscription], user_id: nil)
          cookies.delete(:anonymous_subscription)
        else
          subscription = nil
        end

        if subscription
          subscription.user_id = @user.id
          subscription.save!
          redirect_to SubscriptionsHelper.setup_path(subscription), notice: "Thank you for signing up!"
        else
          redirect_to subscriptions_path, notice: "Thank you for signing up!"
        end
      else
        render "signup_login/signup"
      end
    end
  end

  def settings
    @user_settings = @current_user.user_settings
    @timezone_options = TimezoneHelper::FRIENDLY_NAME_BY_GROUP_ID.map { |pair| pair.reverse }
    timezone = TZInfo::Timezone.get(@user_settings.timezone)
    @server_offset_min = timezone.observed_utc_offset / 60
    if TimezoneHelper::GROUP_ID_BY_TIMEZONE_ID.include?(@user_settings.timezone)
      @selected_option = TimezoneHelper::GROUP_ID_BY_TIMEZONE_ID[@user_settings.timezone]
    else
      offset = timezone.base_utc_offset
      offset_sign = offset >= 0 ? "+" : "-"
      offset_hour = ((offset.abs / 60) % 60).to_s.rjust(2, "0")
      offset_minute = (offset.abs / 3600).to_s.rjust(2, "0")
      friendly_identifier = "#{offset_sign}#{offset_hour}:#{offset_minute}) #{@user_settings.timezone.friendly_identifier}"
      @timezone_options << [friendly_identifier, user_settings.timezone]
      @selected_option = @user_settings.timezone
    end

    render layout: "application"
  end

  def save_timezone
    update_params = params.permit(:timezone, :client_timezone, :client_offset, :version)
    new_version = update_params[:version].to_i
    new_timezone_id = update_params[:timezone]
    unless TimezoneHelper::TZINFO_ALL_TIMEZONES.include?(new_timezone_id)
      raise "Unknown timezone: #{new_timezone_id}"
    end
    new_timezone = TZInfo::Timezone.get(new_timezone_id)

    # Saving timezone may race with user's update rss job.
    # If the job is already running, wait till it finishes, otherwise lock the row so it doesn't start
    failed_lock_attempts = 0
    loop do
      result = ActiveRecord::Base.transaction do
        Rails.logger.info("Locking daily jobs")
        jobs = UserJobHelper::lock_daily_jobs(@current_user.id)
        Rails.logger.info("Locked daily jobs #{jobs}")

        unless jobs.all? { |job| job.locked_by.nil? }
          Rails.logger.info("Some jobs are running, unlocking #{jobs}")
          next
        end

        update_rss_job = jobs.find { |job| job.type == "UpdateRssJob" }
        email_posts_job = jobs.find { |job| job.type == "EmailPostsJob" }
        unless jobs.length == 2 && update_rss_job && email_posts_job
          Rails.logger.warn("Unexpected amount of job rows for the user: #{jobs}")
          next
        end

        user_settings = @current_user.user_settings
        if user_settings.version >= new_version
          Rails.logger.info("Version conflict: existing #{user_settings.version}, new #{new_version}")
          next render status: :conflict, json: { version: user_settings.version }
        end

        user_settings.timezone = new_timezone_id
        user_settings.version = new_version
        user_settings.save!

        rss_job_date_str = UserJobHelper::get_next_scheduled_date(UpdateRssJob, @current_user.id)
        rss_job_date = Date.parse(rss_job_date_str)
        rss_job_new_run_at_local = new_timezone.local_datetime(
          rss_job_date.year, rss_job_date.month, rss_job_date.day, UpdateRssJob::HOUR_OF_DAY, 0, 0
        )
        rss_job_new_run_at = new_timezone.local_to_utc(rss_job_new_run_at_local)
        utc_now = DateTime.now.utc
        if rss_job_new_run_at > utc_now
          UserJobHelper::update_run_at(update_rss_job.id, rss_job_new_run_at)
        else
          # If UpdateRssJob moves to the past, EmailPostsJob may also be in the past or fire right after the
          # lock is released, racing UpdateRssJob. Performing it inline makes sure the execution order is
          # correct

          # Schedules tomorrow's one too, important that the new timezone is saved by now
          UpdateRssJob.new(@current_user.id, rss_job_date_str).perform_now
          UserJobHelper::destroy_job(update_rss_job.id)
        end

        email_job_date_str = UserJobHelper::get_next_scheduled_date(EmailPostsJob, @current_user.id)
        email_job_date = Date.parse(email_job_date_str)
        email_job_new_run_at_local = new_timezone.local_datetime(
          email_job_date.year, email_job_date.month, email_job_date.day, EmailPostsJob::HOUR_OF_DAY, 0, 0
        )
        email_job_new_run_at = new_timezone.local_to_utc(email_job_new_run_at_local)

        # Ideally we'd execute EmailPostsJob inline too if it lands in the past, but don't want to call
        # Postmark APIs inside the database lock and frontend click handler. UpdateRssJob is already
        # executed, so running EmailPostsJob in the worker right after will be ok.
        UserJobHelper::update_run_at(email_posts_job.id, email_job_new_run_at)

        Rails.logger.info("Unlocked daily jobs #{jobs}")
        head :ok
      end

      return result if result

      failed_lock_attempts += 1
      if failed_lock_attempts >= 3
        raise "Couldn't lock the job rows"
      end
      sleep(1)
    end
  end
end
