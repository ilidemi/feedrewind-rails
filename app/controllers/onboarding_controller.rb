class OnboardingController < ApplicationController
  before_action :fill_current_user

  # Logout redirects to the landing page and resets the session, and the CSRF token somehow gets messed up
  skip_before_action :verify_authenticity_token, only: :add_landing

  def add
    @start_url = nil
    @feeds = nil
  end

  def add_landing
    blog_or_feeds = OnboardingHelper::discover_feeds(params[:start_url], @current_user)
    if blog_or_feeds.is_a?(Blog)
      redirect_to BlogsHelper.setup_path(blog_or_feeds)
    else
      @start_url = params[:start_url]
      @feeds = blog_or_feeds
      render "add"
    end
  end

  def discover_feeds
    blog_or_feeds = OnboardingHelper::discover_feeds(params[:start_url], @current_user)
    if blog_or_feeds.is_a?(Blog)
      redirect_to BlogsHelper.setup_path(blog_or_feeds)
    else
      @feeds = blog_or_feeds
      respond_to do |format|
        format.js
      end
    end
  end
end
