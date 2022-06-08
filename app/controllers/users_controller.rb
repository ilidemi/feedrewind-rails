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
        if TZInfo::Timezone.all_identifiers.include?(user_params["timezone"])
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
          UserSettings.create!(user_id: @user.id, timezone: @timezone)
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
end
