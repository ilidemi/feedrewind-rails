class SessionsController < ApplicationController
  layout "login_signup"

  def new
    @errors = []
    render "signup_login/login"
  end

  def create
    user = User.find_by_email(params[:email])
    @errors = []
    if user && user.authenticate(params["current-password"])
      session[:user_id] = user.id

      if cookies[:anonymous_subscription]
        subscription = Subscription.find_by(id: cookies[:anonymous_subscription], user_id: nil)
        cookies.delete(:anonymous_subscription)
      else
        subscription = nil
      end

      if subscription
        subscription.user_id = user.id
        subscription.save!
        redirect_to SubscriptionsHelper.setup_path(subscription), notice: "Logged in!"
      else
        redirect_to subscriptions_path, notice: "Logged in!"
      end
    else
      @errors << "Email or password is invalid"
      render "signup_login/login"
    end
  end

  def destroy
    reset_session
    redirect_to root_path, notice: "Logged out!"
  end
end
