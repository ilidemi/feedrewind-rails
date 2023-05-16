class LandingController < ApplicationController
  def index
    fill_current_user

    if @current_user
      return redirect_to "/subscriptions"
    end

    ProductEventHelper::log_visit_add_page(request, @product_user_id, "/", true)

    @screenshot_links = OnboardingHelper::SCREENSHOT_LINKS
    @screenshot_days_of_week = ScheduleHelper::DAYS_OF_WEEK
    @screenshot_schedule_columns = [
      [:add],
      [:add, :selected],
      [:add],
      [:add, :selected],
      [:add],
      [:add, :selected],
      [:add]
    ]
    @suggested_categories = OnboardingHelper::SUGGESTED_CATEGORIES
    @miscellaneous_blogs = OnboardingHelper::MISCELLANEOUS_BLOGS
  end

  def discard
    cookies.delete(:anonymous_subscription)
    redirect_to action: "index"
  end
end
