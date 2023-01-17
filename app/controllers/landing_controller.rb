class LandingController < ApplicationController
  def index
    fill_current_user

    if @current_user
      return redirect_to "/subscriptions"
    end

    ProductEvent::from_request!(
      request,
      product_user_id: @product_user_id,
      event_type: "visit add page",
      event_properties: {
        path: "/",
        referer: request.referer,
        user_is_anonymous: true
      }
    )

    if cookies[:anonymous_subscription]
      @subscription = Subscription.find_by(id: cookies[:anonymous_subscription], user_id: nil)
    else
      @subscription = nil
    end

    @suggested_categories = OnboardingHelper::SUGGESTED_CATEGORIES
    @miscellaneous_blogs = OnboardingHelper::MISCELLANEOUS_BLOGS
  end

  def discard
    cookies.delete(:anonymous_subscription)
    redirect_to action: "index"
  end
end
