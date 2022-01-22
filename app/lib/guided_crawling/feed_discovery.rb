require_relative 'canonical_link'
require_relative 'feed_parsing'
require_relative 'mock_progress_saver'
require_relative 'progress_logger'
require_relative 'util'

DiscoveredStartPage = Struct.new(:url, :final_url, :content)
DiscoveredStartFeed = Struct.new(:title, :url, :final_url, :content)
UnsupportedFeed = Struct.new(:title, :url)
DiscoverFeedsResult = Struct.new(:start_page, :start_feeds, :unsupported_start_feeds)
SingleFeedResult = Struct.new(:start_feed)

def discover_feeds_at_url(start_url, crawl_ctx, http_client, logger)
  mock_progress_logger = ProgressLogger.new(MockProgressSaver.new(logger))

  start_link = to_canonical_link(start_url, logger)
  raise "Bad start url: #{start_url}" if start_link.nil?

  start_result = crawl_request(start_link, true, crawl_ctx, http_client, mock_progress_logger, logger)
  raise "Unexpected start result: #{start_result}" unless start_result.is_a?(Page) && start_result.content

  if is_feed(start_result.content, logger)
    start_feed = get_start_feed(nil, start_result, start_link, logger)
    if start_feed.is_a?(DiscoveredStartFeed)
      return SingleFeedResult.new(start_feed)
    else
      return DiscoverFeedsResult.new(nil, [], [start_feed])
    end
  else
    start_page = DiscoveredStartPage.new(start_link.url, start_result.fetch_uri.to_s, start_result.content)

    feed_titles_links = start_result
      .document
      .xpath("/html/head/link[@rel='alternate']")
      .to_a
      .filter { |link| %w[application/rss+xml application/atom+xml].include?(link["type"]) }
      .map { |link| [link["title"], link["href"]] }
      .map { |title, url| [title, to_canonical_link(url, logger, start_link.uri)] }
      .filter { |_, link| link }
      .filter { |_, link| !link.url.end_with?("?alt=rss") }

    start_feeds = []
    unsupported_start_feeds = []
    feed_titles_links.each do |feed_title, feed_link|
      if feed_link.uri.path.match?("/comments/feed/?$")
        unsupported_start_feeds << UnsupportedFeed.new(feed_title || feed_link.curi, feed_link.url)
        next
      end

      feed_result = crawl_request(feed_link, true, crawl_ctx, http_client, mock_progress_logger, logger)
      unless feed_result.is_a?(Page) && feed_result.content && is_feed(feed_result.content, logger)
        unsupported_start_feeds << UnsupportedFeed.new(feed_title || feed_link.curi, feed_link.url)
        next
      end

      start_feed = get_start_feed(feed_title, feed_result, feed_link, logger)
      if start_feed.is_a?(DiscoveredStartFeed)
        start_feeds << start_feed
      else
        unsupported_start_feeds << start_feed
      end
    end

    if start_feeds.length == 1
      SingleFeedResult.new(start_feeds.first)
    else
      DiscoverFeedsResult.new(start_page, start_feeds, unsupported_start_feeds)
    end
  end
end

def fetch_feed_at_url(feed_url, crawl_ctx, http_client, logger)
  mock_progress_logger = ProgressLogger.new(MockProgressSaver.new(logger))

  feed_link = to_canonical_link(feed_url, logger)
  raise "Bad feed url: #{feed_url}" if feed_link.nil?

  crawl_result = crawl_request(feed_link, true, crawl_ctx, http_client, mock_progress_logger, logger)
  raise "Unexpected crawl result: #{crawl_result}" unless crawl_result.is_a?(Page) && crawl_result.content
  raise "Page is not a feed: #{crawl_result}" unless is_feed(crawl_result.content, logger)

  parse_feed(crawl_result.content, feed_link.uri, logger)
end

def get_start_feed(title, page, link, logger)
  begin
    parsed_feed = parse_feed(page.content, link.uri, logger)
    if parsed_feed.generator == :medium
      feed_title = parsed_feed.title
    else
      feed_title = title || parsed_feed.title
    end
    return DiscoveredStartFeed.new(feed_title, link.url, page.fetch_uri.to_s, page.content)
  rescue => e
    logger.info("Parse feed exception")
    print_nice_error(e).each do |line|
      logger.info(line)
    end

    return UnsupportedFeed.new(link.curi, link.url)
  end
end
