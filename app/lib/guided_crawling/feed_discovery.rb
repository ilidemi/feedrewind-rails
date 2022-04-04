require 'set'
require 'timeout'
require_relative 'canonical_link'
require_relative 'feed_parsing'
require_relative 'mock_progress_saver'
require_relative 'progress_logger'
require_relative 'util'

DiscoveredSingleFeed = Struct.new(:start_page, :feed)
DiscoveredMultipleFeeds = Struct.new(:start_page, :feeds)
DiscoveredFeed = Struct.new(:title, :url)
DiscoveredFetchedFeed = Struct.new(:title, :url, :final_url, :content)
DiscoveredStartPage = Struct.new(:url, :final_url, :content)

def discover_feeds_at_url(start_url, enforce_timeout, crawl_ctx, http_client, logger)
  mock_progress_logger = ProgressLogger.new(MockProgressSaver.new(logger))

  start_link = to_canonical_link(start_url, logger)
  unless start_link
    logger.info("Bad start url: #{start_url}")
    return :discover_could_not_reach
  end

  begin
    start_result = crawl_request_with_timeout(
      start_link, true, enforce_timeout, crawl_ctx, http_client, mock_progress_logger, logger
    )

    if start_result.is_a?(Page) && !start_result.content
      logger.info("Page without content: #{start_result}")
      return :discovered_no_feeds
    end

    unless start_result.is_a?(Page)
      logger.info("Unexpected start result: #{start_result}")
      return :discover_could_not_reach
    end
  rescue => err
    logger.info("Error while getting start_link: #{err.class} (#{err})")
    return :discover_could_not_reach
  end

  if is_feed(start_result.content, logger)
    begin
      parsed_feed = parse_feed(start_result.content, start_link.uri, logger)
      feed_title = parsed_feed.title
      feed = DiscoveredFetchedFeed.new(
        feed_title, start_link.url, start_result.fetch_uri.to_s, start_result.content
      )
      DiscoveredSingleFeed.new(nil, feed)
    rescue => e
      logger.info("Parse feed exception")
      print_nice_error(e).each do |line|
        logger.info(line)
      end

      :discovered_bad_feed
    end
  else
    start_page = DiscoveredStartPage.new(start_link.url, start_result.fetch_uri.to_s, start_result.content)

    feeds = start_result
      .document
      .xpath("//*[self::a or self::area or self::link][@rel='alternate'][@type='application/rss+xml' or @type='application/atom+xml']")
      .to_a
      .filter_map do |link|
      case link.name
      when "a"
        title = link.text
      when "area"
        title = link["alt"]
      else
        # "link"
        title = link["title"]
      end

      url = link["href"]
      canonical_link = to_canonical_link(url, logger, start_link.uri)
      next nil unless canonical_link
      next nil if canonical_link.url.end_with?("?alt=rss")
      next nil if canonical_link.uri.path.match?("/comments/feed/?$")

      DiscoveredFeed.new(title, canonical_link.url)
    end

    dedup_feeds = []
    seen_titles = []
    seen_urls = []
    feeds.each do |feed|
      next if seen_urls.include?(feed.url)

      downcase_url = feed.url.downcase
      next if downcase_url.include?("atom") &&
        seen_urls.include?(downcase_url.sub(/(.+)atom(.*)/, "\\1rss\\2")) # Last occurrence of "atom"
      next if downcase_url.include?("rss") &&
        seen_urls.include?(downcase_url.sub(/(.+)rss(.*)/, "\\1atom\\2")) # Last occurrence of "rss"

      downcase_title = feed.title&.downcase
      next if downcase_title == "atom" && seen_titles.include?("rss")
      next if downcase_title == "rss" && seen_titles.include?("atom")

      dedup_feeds << feed
      seen_titles << downcase_title
      seen_urls << downcase_url
    end

    dedup_feeds.each do |feed|
      if feed.title.nil? || %w[rss atom].include?(feed.title.downcase)
        feed.title = start_result.document.title || start_result.fetch_uri.host
      end
    end

    if dedup_feeds.length == 0
      :discovered_no_feeds
    elsif dedup_feeds.length == 1
      #noinspection RubyNilAnalysis
      single_feed_result = fetch_feed_at_url(
        dedup_feeds.first.url, enforce_timeout, crawl_ctx, http_client, logger
      )
      if single_feed_result.is_a?(Page)
        #noinspection RubyNilAnalysis
        fetched_feed = DiscoveredFetchedFeed.new(
          dedup_feeds.first.title,
          dedup_feeds.first.url,
          single_feed_result.fetch_uri.to_s,
          single_feed_result.content
        )
        DiscoveredSingleFeed.new(start_page, fetched_feed)
      elsif single_feed_result == :discovered_bad_feed
        return :discovered_bad_feed
      elsif single_feed_result == :discovered_timeout_feed
        DiscoveredSingleFeed.new(start_page, dedup_feeds.first)
      else
        raise "Unexpected result from fetch_feed_at_url: #{single_feed_result}"
      end
    else
      DiscoveredMultipleFeeds.new(start_page, dedup_feeds)
    end
  end
end

def fetch_feed_at_url(feed_url, enforce_timeout, crawl_ctx, http_client, logger)
  mock_progress_logger = ProgressLogger.new(MockProgressSaver.new(logger))

  feed_link = to_canonical_link(feed_url, logger)
  if feed_link.nil?
    logger.info("Bad feed url: #{feed_url}")
    return :discovered_bad_feed
  end

  begin
    crawl_result = crawl_request_with_timeout(
      feed_link, true, enforce_timeout, crawl_ctx, http_client, mock_progress_logger, logger
    )
    unless crawl_result.is_a?(Page) && crawl_result.content
      logger.info("Unexpected crawl result: #{crawl_result}")
      return :discovered_bad_feed
    end

    unless is_feed(crawl_result.content, logger)
      logger.info("Page is not a feed: #{crawl_result}")
      return :discovered_bad_feed
    end

    crawl_result
  rescue Timeout::Error
    logger.info("Timeout while fetching a feed")
    :discovered_timeout_feed
  end
end

def crawl_request_with_timeout(
  link, is_feed_expected, enforce_timeout, crawl_ctx, http_client, progress_logger, logger
)
  if enforce_timeout
    Timeout::timeout(10) do
      crawl_request(link, is_feed_expected, crawl_ctx, http_client, progress_logger, logger)
    end
  else
    crawl_request(link, is_feed_expected, crawl_ctx, http_client, progress_logger, logger)
  end
end