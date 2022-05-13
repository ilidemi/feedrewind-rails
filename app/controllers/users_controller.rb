class UsersController < ApplicationController
  layout "login_signup"

  def new
    @user = User.new
    render "signup_login/signup"
  end

  def create
    user_params = params.permit(:email, "new-password")
    User.transaction do
      existing_user = User.find_by(email: user_params["email"])
      if existing_user && existing_user.password_digest.nil?
        @user = existing_user
        @user.password = user_params["new-password"]
      else
        @user = User.new({ email: user_params["email"], password: user_params["new-password"] })
      end

      if @user.save
        unless existing_user
          UpdateRssJob.schedule_for_tomorrow(@user.id)
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
