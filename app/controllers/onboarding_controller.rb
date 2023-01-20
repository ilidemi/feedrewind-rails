require_relative '../lib/guided_crawling/crawling'
require_relative '../lib/guided_crawling/hardcoded_blogs'
require_relative '../lib/guided_crawling/http_client'
require_relative '../lib/guided_crawling/feed_discovery'

class OnboardingController < ApplicationController
  before_action :fill_current_user

  # Logout redirects to the landing page and resets the session, and the CSRF token somehow gets messed up
  skip_before_action :verify_authenticity_token, only: :add_landing

  def add
    if params[:start_url]
      path = "/subscriptions/add?start_url="
      ProductEventHelper::log_visit_add_page(
        request, @product_user_id, path, @current_user.nil?, { blog_url: params[:start_url] }
      )
      start_url = params[:start_url].strip
      discover_feeds_result, result_code = discover_feeds_internal(start_url, @current_user, @product_user_id)
      ProductEventHelper::log_discover_feeds(
        request, @product_user_id, @current_user.nil?, start_url, result_code
      )
      TypedBlogUrl.create!(
        typed_url: params[:start_url],
        stripped_url: start_url,
        source: path,
        result: result_code,
        user_id: @current_user&.id
      )
      if discover_feeds_result.is_a?(Subscription)
        subscription = discover_feeds_result
        ProductEventHelper::log_create_subscription(
          request, @product_user_id, @current_user.nil?, subscription
        )
        redirect_to SubscriptionsHelper.setup_path(subscription)
      elsif discover_feeds_result.is_a?(Subscription::BlogNotSupported)
        redirect_to BlogsHelper.unsupported_path(discover_feeds_result.blog)
      else
        @feeds_data = discover_feeds_result
        render "add"
      end
    else
      ProductEventHelper::log_visit_add_page(
        request, @product_user_id, "/subscriptions/add", @current_user.nil?
      )

      @feeds_data = nil
      @suggested_categories = OnboardingHelper::SUGGESTED_CATEGORIES
      @miscellaneous_blogs = OnboardingHelper::MISCELLANEOUS_BLOGS
    end
  end

  def add_landing
    start_url = params[:start_url].strip
    discover_feeds_result, result_code = discover_feeds_internal(start_url, @current_user, @product_user_id)
    ProductEventHelper::log_discover_feeds(
      request, @product_user_id, @current_user.nil?, start_url, result_code
    )
    TypedBlogUrl.create!(
      typed_url: params[:start_url],
      stripped_url: start_url,
      source: "/",
      result: result_code,
      user_id: @current_user&.id
    )
    if discover_feeds_result.is_a?(Subscription)
      subscription = discover_feeds_result
      ProductEventHelper::log_create_subscription(request, @product_user_id, @current_user.nil?, subscription)
      redirect_to SubscriptionsHelper.setup_path(subscription)
    elsif discover_feeds_result.is_a?(Subscription::BlogNotSupported)
      redirect_to BlogsHelper.unsupported_path(discover_feeds_result.blog)
    else
      @feeds_data = discover_feeds_result
      render "add"
    end
  end

  def discover_feeds
    start_url = params[:start_url].strip
    discover_feeds_result, result_code = discover_feeds_internal(start_url, @current_user, @product_user_id)
    ProductEventHelper::log_discover_feeds(
      request, @product_user_id, @current_user.nil?, start_url, result_code
    )
    TypedBlogUrl.create!(
      typed_url: params[:start_url],
      stripped_url: start_url,
      source: "/subscriptions/add",
      result: result_code,
      user_id: @current_user&.id
    )
    if discover_feeds_result.is_a?(Subscription)
      subscription = discover_feeds_result
      ProductEventHelper::log_create_subscription(request, @product_user_id, @current_user.nil?, subscription)
      render plain: SubscriptionsHelper.setup_path(subscription)
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

  FeedsData = Struct.new(:start_url, :feeds, :not_a_url, :are_no_feeds, :could_not_reach, :bad_feed)

  def discover_feeds_internal(start_url, user, product_user_id)
    if start_url == HardcodedBlogs::OUR_MACHINERY
      blog = Blog::find_by(feed_url: HardcodedBlogs::OUR_MACHINERY, version: Blog::LATEST_VERSION)
      subscription = Subscription::create_for_blog(blog, user, product_user_id)
      return [subscription, "hardcoded"]
    end

    crawl_ctx = CrawlContext.new
    http_client = HttpClient.new(false)
    discovered_feeds = discover_feeds_at_url(start_url, true, crawl_ctx, http_client, Rails.logger)

    if discovered_feeds.is_a?(DiscoveredSingleFeed)
      discovered_start_page = discovered_feeds.start_page
      if discovered_feeds.start_page
        start_page = StartPage.new(
          url: discovered_start_page.url,
          final_url: discovered_start_page.final_url,
          content: discovered_start_page.content
        )
        start_page.save!
      else
        start_page = nil
      end

      discovered_feed = discovered_feeds.feed
      if discovered_feed.is_a?(DiscoveredFetchedFeed)
        start_feed = StartFeed.new(
          url: discovered_feed.url,
          final_url: discovered_feed.final_url,
          content: discovered_feed.content,
          title: discovered_feed.title,
          start_page_id: start_page&.id
        )
        start_feed.save!

        updated_blog = Blog::create_or_update(start_feed)
        subscription_or_blog_not_supported = Subscription::create_for_blog(
          updated_blog, user, product_user_id
        )
        result_code = subscription_or_blog_not_supported.is_a?(Subscription) ? "feed" : "known_unsupported"
        [subscription_or_blog_not_supported, result_code]
      else
        start_feed = StartFeed.new(
          url: discovered_feed.url,
          final_url: nil,
          content: nil,
          title: discovered_feed.title,
          start_page_id: start_page&.id
        )
        start_feed.save!

        [FeedsData.new(start_url, [start_feed], nil, nil, nil), "page_with_feed"]
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
          title: feed.title,
          start_page_id: start_page.id
        )
        start_feed.save!
        start_feeds << start_feed
      end

      [FeedsData.new(start_url, start_feeds, nil, nil, nil), "page_with_multiple_feeds"]
    elsif discovered_feeds == :discovered_not_a_url
      [FeedsData.new(start_url, nil, true, nil, nil, nil), "not_a_url"]
    elsif discovered_feeds == :discovered_no_feeds
      [FeedsData.new(start_url, nil, nil, true, nil, nil), "no_feeds"]
    elsif discovered_feeds == :discover_could_not_reach
      [FeedsData.new(start_url, nil, nil, nil, true, nil), "could_not_reach"]
    elsif discovered_feeds == :discovered_bad_feed
      [FeedsData.new(start_url, nil, nil, nil, nil, true), "bad_feed"]
    else
      raise "Unexpected result from discover_feeds_at_url: #{discovered_feeds}"
    end
  end
end
