class LandingController < ApplicationController
  def index
    fill_current_user

    if @current_user
      return redirect_to "/subscriptions"
    end

    ProductEventHelper::log_visit_add_page(request, @product_user_id, "/", true)

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
