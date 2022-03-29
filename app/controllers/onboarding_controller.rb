require_relative '../lib/guided_crawling/crawling'
require_relative '../lib/guided_crawling/http_client'
require_relative '../lib/guided_crawling/feed_discovery'

class OnboardingController < ApplicationController
  before_action :fill_current_user

  # Logout redirects to the landing page and resets the session, and the CSRF token somehow gets messed up
  skip_before_action :verify_authenticity_token, only: :add_landing

  def add
    @feeds_data = nil
  end

  def add_landing
    discover_feeds_result = discover_feeds_internal(params[:start_url], @current_user)
    if discover_feeds_result.is_a?(Subscription)
      redirect_to SubscriptionsHelper.setup_path(discover_feeds_result)
    elsif discover_feeds_result.is_a?(Subscription::BlogNotSupported)
      redirect_to BlogsHelper.unsupported_path(discover_feeds_result.blog)
    else
      @start_url = params[:start_url]
      @feeds_data = discover_feeds_result
      render "add"
    end
  end

  def discover_feeds
    discover_feeds_result = discover_feeds_internal(params[:start_url], @current_user)
    if discover_feeds_result.is_a?(Subscription)
      render plain: SubscriptionsHelper.setup_path(discover_feeds_result)
    elsif discover_feeds_result.is_a?(Subscription::BlogNotSupported)
      render plain: BlogsHelper.unsupported_path(discover_feeds_result.blog)
    else
      @feeds_data = discover_feeds_result
      respond_to do |format|
        format.js
      end
    end
  end

  private

  FeedsData = Struct.new(:start_url, :start_page_id, :feeds, :are_no_feeds, :could_not_reach, :bad_feed)

  def discover_feeds_internal(start_url, user)
    crawl_ctx = CrawlContext.new
    http_client = HttpClient.new(false)
    discovered_feeds = discover_feeds_at_url(start_url, crawl_ctx, http_client, Rails.logger)

    if discovered_feeds.is_a?(DiscoveredSingleFeed)
      feed = discovered_feeds.feed
      if feed.is_a?(DiscoveredFetchedFeed)
        start_feed = StartFeed.new(
          url: feed.url,
          final_url: feed.final_url,
          content: feed.content,
          title: feed.title
        )
        start_feed.save!

        updated_blog = Blog::create_or_update(nil, start_feed.id, start_feed.final_url, feed.title)
        subscription_or_blog_not_supported = Subscription::create_for_blog(updated_blog, user)
        subscription_or_blog_not_supported
      else
        start_feed = StartFeed.new(
          url: feed.url,
          final_url: nil,
          content: nil,
          title: feed.title
        )
        start_feed.save!

        FeedsData.new(nil, nil, [start_feed], nil, nil, nil)
      end
    elsif discovered_feeds.is_a?(DiscoveredMultipleFeeds)
      start_page = StartPage.new(
        url: discovered_feeds.start_page.url,
        final_url: discovered_feeds.start_page.final_url,
        content: discovered_feeds.start_page.content
      )
      start_page.save!

      start_feeds = []
      discovered_feeds.feeds.each do |feed|
        start_feed = StartFeed.new(
          url: feed.url,
          final_url: nil,
          content: nil,
          title: feed.title
        )
        start_feed.save!
        start_feeds << start_feed
      end

      FeedsData.new(nil, start_page.id, start_feeds, nil, nil, nil)
    elsif discovered_feeds == :discovered_no_feeds
      FeedsData.new(start_url, nil, nil, true, nil, nil)
    elsif discovered_feeds == :discover_could_not_reach
      FeedsData.new(start_url, nil, nil, nil, true, nil)
    elsif discovered_feeds == :discovered_bad_feed
      FeedsData.new(start_url, nil, nil, nil, nil, true)
    else
      raise "Unexpected result from discover_feeds_at_url: #{discovered_feeds}"
    end
  end
end
