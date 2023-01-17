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
    fill_current_user # for product analytics

    login_params = params.permit(:email, "current-password", :redirect)
    user = User.find_by_email(login_params[:email])
    @errors = []
    if user && user.authenticate(login_params["current-password"])
      session[:auth_token] = user.auth_token

      if cookies[:anonymous_subscription]
        subscription = Subscription.find_by(id: cookies[:anonymous_subscription], user_id: nil)
        cookies.delete(:anonymous_subscription)
      else
        subscription = nil
      end

      # Users visiting landing page then signing in need to be excluded from the sign up funnel
      # Track them twice: first as anonymous, then properly
      ProductEvent::from_request!(
        request,
        product_user_id: @product_user_id,
        event_type: "log in",
        event_properties: {
          user_is_anonymous: true
        }
      )
      ProductEvent::from_request!(
        request,
        product_user_id: user.product_user_id,
        event_type: "log in",
        event_properties: {
          user_is_anonymous: false
        }
      )

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
