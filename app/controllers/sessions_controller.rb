class SessionsController < ApplicationController
  layout "login_signup"

  def new
    if current_user
      return redirect_to root_path
    end

    @errors = []
    @redirect = request.query_parameters["redirect"]
    render "signup_login/login"
  end

  def create
    login_params = params.permit(:email, "current-password", :redirect)
    user = User.find_by_email(login_params[:email])
    @errors = []
    if user && user.authenticate(login_params["current-password"])
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
        redirect_to SubscriptionsHelper.setup_path(subscription)
      elsif login_params[:redirect]
        redirect_to login_params[:redirect]
      else
        redirect_to subscriptions_path
      end
    else
      @errors << "Email or password is invalid"
      render "signup_login/login"
    end
  end

  def destroy
    reset_session
    redirect_to root_path
  end
end
