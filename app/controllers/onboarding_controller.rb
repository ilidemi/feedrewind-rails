require_relative '../lib/guided_crawling/crawling'
require_relative '../lib/guided_crawling/http_client'
require_relative '../lib/guided_crawling/feed_discovery'

class OnboardingController < ApplicationController
  before_action :fill_current_user

  # Logout redirects to the landing page and resets the session, and the CSRF token somehow gets messed up
  skip_before_action :verify_authenticity_token, only: :add_landing

  def add
    @start_url = nil
    @feeds = nil
  end

  def add_landing
    subscription_or_feeds_or_blog_not_supported = discover_feeds_internal(params[:start_url], @current_user)
    if subscription_or_feeds_or_blog_not_supported.is_a?(Subscription)
      redirect_to SubscriptionsHelper.setup_path(subscription_or_feeds_or_blog_not_supported)
    elsif subscription_or_feeds_or_blog_not_supported.is_a?(Feeds)
      @start_url = params[:start_url]
      @feeds = subscription_or_feeds_or_blog_not_supported
      render "add"
    elsif subscription_or_feeds_or_blog_not_supported.is_a?(Subscription::BlogNotSupported)
      redirect_to BlogsHelper.unsupported_path(subscription_or_feeds_or_blog_not_supported.blog)
    else
      raise "Unexpected result from discover_feeds_internal: #{subscription_or_feeds_or_blog_not_supported}"
    end
  end

  def discover_feeds
    subscription_or_feeds_or_blog_not_supported = discover_feeds_internal(params[:start_url], @current_user)
    if subscription_or_feeds_or_blog_not_supported.is_a?(Subscription)
      render plain: SubscriptionsHelper.setup_path(subscription_or_feeds_or_blog_not_supported)
    elsif subscription_or_feeds_or_blog_not_supported.is_a?(Feeds)
      @feeds = subscription_or_feeds_or_blog_not_supported
      respond_to do |format|
        format.js
      end
    elsif subscription_or_feeds_or_blog_not_supported.is_a?(Subscription::BlogNotSupported)
      render plain: BlogsHelper.unsupported_path(subscription_or_feeds_or_blog_not_supported.blog)
    else
      raise "Unexpected result from discover_feeds_internal: #{subscription_or_feeds_or_blog_not_supported}"
    end
  end

  private

  Feeds = Struct.new(:start_page_id, :supported_feeds, :unsupported_feeds)

  def discover_feeds_internal(start_url, user)
    crawl_ctx = CrawlContext.new
    http_client = HttpClient.new(false)
    discover_feeds_result = discover_feeds_at_url(start_url, crawl_ctx, http_client, Rails.logger)

    if discover_feeds_result.is_a?(SingleFeedResult)
      start_feed = StartFeed.new(
        url: discover_feeds_result.start_feed.url,
        final_url: discover_feeds_result.start_feed.final_url,
        content: discover_feeds_result.start_feed.content,
        title: discover_feeds_result.start_feed.title
      )
      start_feed.save!

      updated_blog = Blog::create_or_update(
        nil, start_feed.id, start_feed.final_url, discover_feeds_result.start_feed.title
      )
      subscription_or_blog_not_supported = Subscription::create_for_blog(updated_blog, user)
      subscription_or_blog_not_supported
    else
      start_page = StartPage.new(
        url: discover_feeds_result.start_page.url,
        final_url: discover_feeds_result.start_page.final_url,
        content: discover_feeds_result.start_page.content
      )
      start_page.save!

      start_feeds = []
      discover_feeds_result.start_feeds.each do |discovered_start_feed|
        start_feed = StartFeed.new(
          url: discovered_start_feed.url,
          final_url: discovered_start_feed.final_url,
          content: discovered_start_feed.content,
          title: discovered_start_feed.title
        )
        start_feed.save!
        start_feeds << start_feed
      end

      Feeds.new(start_page.id, start_feeds, discover_feeds_result.unsupported_start_feeds)
    end
  end
end
