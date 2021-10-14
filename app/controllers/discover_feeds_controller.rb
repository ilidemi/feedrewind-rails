require_relative '../lib/guided_crawling/crawling'
require_relative '../lib/guided_crawling/http_client'
require_relative '../lib/guided_crawling/feed_discovery'

class DiscoverFeedsController < ApplicationController
  before_action :authorize

  def discover
    crawl_ctx = CrawlContext.new
    http_client = HttpClient.new(false)
    discover_feeds_result = discover_feeds(params[:start_url], crawl_ctx, http_client, Rails.logger)

    if discover_feeds_result.is_a?(SingleFeedResult)
      start_feed = StartFeed.new(
        url: discover_feeds_result.start_feed.url,
        final_url: discover_feeds_result.start_feed.final_url,
        content: discover_feeds_result.start_feed.content,
        title: discover_feeds_result.start_feed.title
      )
      start_feed.save!

      blog = BlogsHelper.create(
        nil, start_feed.id, start_feed.final_url, discover_feeds_result.start_feed.title, @current_user
      )

      redirect_to BlogsHelper.setup_url(request, blog)
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

      @start_page_id = start_page.id
      @start_feeds = start_feeds
      @unsupported_start_feeds = discover_feeds_result.unsupported_start_feeds
      respond_to do |format|
        format.js
      end
    end
  end
end
