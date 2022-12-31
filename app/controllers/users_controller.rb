require 'tzinfo'

class UsersController < ApplicationController
  layout "login_signup"
  before_action :authorize, except: [:new, :create]

  def new
    if current_user
      return redirect_to root_path
    end

    @user = User.new
    render "signup_login/signup"
  end

  def create
    user_params = params.permit(:email, "new-password", :timezone, :time_offset)
    User.transaction do
      email = user_params[:email]
      password = user_params["new-password"]
      existing_user = User.find_by(email: email)
      if existing_user && existing_user.password_digest.nil?
        @user = existing_user
        @user.password = password
      else
        name = email[...email.index("@")]
        @user = User.new(
          {
            email: email,
            password: password,
            name: name
          }
        )

        params_timezone = user_params[:timezone]
        params_offset = user_params[:time_offset]
        Rails.logger.info("Timezone in: #{params_timezone}, offset in: #{params_offset}")
        if TimezoneHelper::TZINFO_ALL_TIMEZONES.include?(params_timezone)
          @timezone = params_timezone
        else
          Rails.logger.warn("Unknown timezone: #{params_timezone}")
          offset_hours_inverted = (params_offset.to_f / 60).round
          if -14 <= offset_hours_inverted && offset_hours_inverted <= 12
            offset_str = offset_hours_inverted >= 0 ? "+#{offset_hours_inverted}" : offset_hours_inverted.to_s
            @timezone = "Etc/GMT#{offset_str}"
          else
            @timezone = "UTC"
          end
        end
        Rails.logger.info("Timezone out: #{@timezone}")
      end

      return render "signup_login/signup" unless @user.save

      unless existing_user
        UserSettings.create!(
          user_id: @user.id,
          timezone: @timezone,
          delivery_channel: nil,
          version: 1
        )
      end

      NotifySlackJob.perform_later("*#{NotifySlackJob::escape(@user.email)}* signed up")

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
        redirect_to SubscriptionsHelper.setup_path(subscription)
      else
        redirect_to subscriptions_path
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
        Rails.logger.info("Locking PublishPostsJob")
        jobs = PublishPostsJob::lock(@current_user.id)
        Rails.logger.info("Locked PublishPostsJob #{jobs}")

        unless jobs.all? { |job| job.locked_by.nil? }
          Rails.logger.info("Some jobs are running, unlocking #{jobs}")
          next
        end

        user_settings = @current_user.user_settings
        unless (user_settings.delivery_channel && jobs.length == 1) ||
          (!user_settings.delivery_channel && jobs.length == 0)

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

        if jobs.length == 1
          publish_posts_job = jobs.first
          job_date_str = PublishPostsJob::get_next_scheduled_date(@current_user.id)
          job_date = Date.parse(job_date_str)
          job_hour = PublishPostsJob::get_hour_of_day(user_settings.delivery_channel)
          job_new_run_at = PublishPostsJob::safe_local_to_utc(
            new_timezone, DateTime.new(job_date.year, job_date.month, job_date.day, job_hour, 0, 0)
          )
          PublishPostsJob::update_run_at(publish_posts_job.id, job_new_run_at)
        end

        Rails.logger.info("Unlocked PublishPostsJob #{jobs}")
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

  def save_delivery_channel
    update_params = params.permit(:delivery_channel, :client_timezone, :client_offset, :version)
    new_version = update_params[:version].to_i
    case update_params[:delivery_channel]
    when "rss"
      new_delivery_channel = "multiple_feeds"
    when "email"
      new_delivery_channel = "email"
    else
      raise "Unknown delivery channel: #{update_params[:delivery_channel]}"
    end

    # Saving delivery channel may race with user's update rss job.
    # If the job is already running, wait till it finishes, otherwise lock the row so it doesn't start
    failed_lock_attempts = 0
    loop do
      result = ActiveRecord::Base.transaction do
        Rails.logger.info("Locking PublishPostsJob")
        jobs = PublishPostsJob::lock(@current_user.id)
        Rails.logger.info("Locked PublishPostsJob #{jobs}")

        unless jobs.all? { |job| job.locked_by.nil? }
          Rails.logger.info("Some jobs are running, unlocking #{jobs}")
          next
        end

        user_settings = @current_user.user_settings
        unless (user_settings.delivery_channel && jobs.length == 1) ||
          (!user_settings.delivery_channel && jobs.length == 0)

          Rails.logger.warn("Unexpected amount of job rows for the user: #{jobs}")
          next
        end

        if user_settings.version >= new_version
          Rails.logger.info("Version conflict: existing #{user_settings.version}, new #{new_version}")
          next render status: :conflict, json: { version: user_settings.version }
        end

        user_settings.delivery_channel = new_delivery_channel
        user_settings.version = new_version
        user_settings.save!

        job_date_str = PublishPostsJob::get_next_scheduled_date(@current_user.id)
        if job_date_str
          publish_posts_job = jobs.first
          job_date = Date.parse(job_date_str)
          job_hour = PublishPostsJob::get_hour_of_day(user_settings.delivery_channel)
          timezone = TZInfo::Timezone.get(user_settings.timezone)
          job_new_run_at = PublishPostsJob::safe_local_to_utc(
            timezone, DateTime.new(job_date.year, job_date.month, job_date.day, job_hour, 0, 0)
          )
          PublishPostsJob::update_run_at(publish_posts_job.id, job_new_run_at)
          Rails.logger.info("Rescheduled PublishPostsJob for #{job_new_run_at}")
        else
          PublishPostsJob::initial_schedule(@current_user)
          Rails.logger.info("Did initial schedule for PublishPostsJob")
        end

        Rails.logger.info("Unlocked PublishPostsJob #{jobs}")
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
