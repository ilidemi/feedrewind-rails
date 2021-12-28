class UsersController < ApplicationController
  def new
    @user = User.new
  end

  def create
    user_params = params.require(:user).permit(:email, :password, :password_confirmation)
    @user = User.new(user_params)
    if @user.save
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
      render :new
    end
  end
end
