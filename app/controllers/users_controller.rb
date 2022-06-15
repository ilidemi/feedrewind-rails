require 'tzinfo'

class UsersController < ApplicationController
  layout "login_signup"

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
          UserSettings.create!(user_id: @user.id, timezone: @timezone, version: 1)
          UpdateRssJob.initial_schedule(@user)
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
    authorize
    @user_settings = @current_user.user_settings
    @timezone_options = TimezoneHelper::FRIENDLY_NAME_BY_GROUP_ID.map { |pair| pair.reverse }
    if TimezoneHelper::GROUP_ID_BY_TIMEZONE_ID.include?(@user_settings.timezone)
      @selected_option = TimezoneHelper::GROUP_ID_BY_TIMEZONE_ID[@user_settings.timezone]
    else
      offset = @user_settings.timezone.observed_utc_offset
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
    authorize
    update_params = params.permit(:timezone, :version)
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
        Rails.logger.info("Locking UpdateRssJob")
        jobs = UpdateRssJob.lock(@current_user.id)
        Rails.logger.info("Locked UpdateRssJob #{jobs}")

        unless jobs.values.all?(&:nil?)
          Rails.logger.info("Some jobs are running, unlocking #{jobs.keys}")
          next
        end

        unless jobs.length == 1
          Rails.logger.warn("Multiple job rows for the user: #{jobs.keys}")
          next
        end

        user_settings = @current_user.user_settings
        if user_settings.version >= new_version
          next render status: :conflict, json: { version: user_settings.version }
        end

        date_str = UpdateRssJob.get_next_scheduled_date(@current_user.id)
        date = Date.parse(date_str)
        new_run_at_local = new_timezone.local_datetime(date.year, date.month, date.day, 2, 0, 0)
        new_run_at = new_timezone.local_to_utc(new_run_at_local)
        UpdateRssJob.update_run_at(jobs.keys.first, new_run_at)

        user_settings.timezone = new_timezone_id
        user_settings.version = new_version
        user_settings.save!
        Rails.logger.info("Unlocked UpdateRssJob #{jobs.keys}")
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
