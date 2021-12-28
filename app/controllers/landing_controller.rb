class LandingController < ApplicationController
  def index
    if cookies[:anonymous_subscription]
      @subscription = Subscription.find_by(id: cookies[:anonymous_subscription], user_id: nil)
    else
      @subscription = nil
    end
  end

  def discard
    cookies.delete(:anonymous_subscription)
    redirect_to action: "index"
  end
end
