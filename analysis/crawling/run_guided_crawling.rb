require_relative '../../app/lib/guided_crawling/feed_discovery'
require_relative '../../app/lib/guided_crawling/guided_crawling'
require_relative '../../app/lib/guided_crawling/mock_progress_saver'
require_relative '../../app/lib/guided_crawling/progress_logger'
require_relative 'mock_http_client'
require_relative 'mock_puppeteer_client'
require_relative 'run_common'

GUIDED_CRAWLING_RESULT_COLUMNS = [
  [:start_url, :neutral],
  [:source, :neutral],
  [:comment, :neutral],
  [:gt_pattern, :neutral],
  [:feed_url, :boolean],
  [:feed_links, :boolean],
  [:duplicate_fetches, :neutral],
  [:no_guided_regression, :neutral],
  [:historical_links_found, :boolean],
  [:historical_links_matching, :boolean],
  [:historical_links_pattern, :neutral_present],
  [:historical_links_count, :neutral_present],
  [:historical_links_titles_matching, :neutral_present],
  [:main_url, :neutral_present],
  [:oldest_link, :neutral_present],
  [:extra, :neutral],
  [:total_requests, :neutral],
  [:total_pages, :neutral],
  [:total_network_requests, :neutral],
  [:title_requests, :neutral],
  [:total_time, :neutral]
]

class GuidedCrawlRunnable
  def initialize
    @result_column_names = to_column_names(GUIDED_CRAWLING_RESULT_COLUMNS)
  end

  def run(start_link_id, save_successes, allow_puppeteer, db, logger)
    run_guided_crawl(start_link_id, save_successes, allow_puppeteer, db, logger)
  end

  attr_reader :result_column_names
end

def run_guided_crawl(start_link_id, save_successes, allow_puppeteer, db, logger)
  start_link_row = db.exec_params('select source, url, rss_url from start_links where id = $1', [start_link_id])[0]
  start_link_url = start_link_row["url"]
  start_link_feed_url = start_link_row["rss_url"]
  result = RunResult.new(GUIDED_CRAWLING_RESULT_COLUMNS)
  result.start_url = "<a href=\"#{start_link_url}\">#{start_link_url}</a>" if start_link_url
  result.source = start_link_row["source"]
  crawl_ctx = CrawlContext.new
  start_time = monotonic_now

  begin
    comment_row = db.exec_params(
      'select severity, issue from known_issues where start_link_id = $1',
      [start_link_id]
    ).first
    if comment_row
      result.comment = comment_row["issue"]
      if comment_row["severity"] == "fail"
        result.comment_status = :failure
        raise "Known issue: #{comment_row["issue"]}"
      end

      if allow_puppeteer && comment_row["issue"].start_with?("javascript")
        logger.info("Emptying mock pages and redirects to rerun puppeteer")
        db.exec_params("delete from mock_responses where start_link_id = $1", [start_link_id])
      end
    end

    gt_row = db.exec_params(
      "select pattern, entries_count, main_page_canonical_url, oldest_entry_canonical_url from historical_ground_truth where start_link_id = $1",
      [start_link_id]
    ).first
    if gt_row
      result.gt_pattern = gt_row["pattern"]
    end

    mock_http_client = MockHttpClient.new(db, start_link_id)
    if allow_puppeteer
      db.exec_params('delete from mock_puppeteer_pages where start_link_id = $1', [start_link_id])
      puppeteer_client = CachingPuppeteerClient.new(db, start_link_id)
    else
      puppeteer_client = MockPuppeteerClient.new(db, start_link_id)
    end
    db.exec_params('delete from historical where start_link_id = $1', [start_link_id])

    discover_feeds_result = discover_feeds_at_url(
      start_link_feed_url || start_link_url, crawl_ctx, mock_http_client, logger
    )

    if discover_feeds_result.is_a?(SingleFeedResult)
      discovered_start_page = nil
      discovered_start_feed = discover_feeds_result.start_feed
    else
      raise "No feeds discovered" if discover_feeds_result.start_feeds.empty?
      raise "More than one feed discovered" if discover_feeds_result.start_feeds.length > 1

      discovered_start_page = discover_feeds_result.start_page
      discovered_start_feed = discover_feeds_result.start_feeds.first
    end

    progress_saver = MockProgressSaver.new(logger)
    guided_crawl_result = guided_crawl(
      discovered_start_page, discovered_start_feed, crawl_ctx, mock_http_client, puppeteer_client,
      progress_saver, logger
    )
    result.feed_url = guided_crawl_result.feed_result.feed_url
    result.feed_links = guided_crawl_result.feed_result.feed_links
    result.start_url = guided_crawl_result.start_url
    historical_result = guided_crawl_result.historical_result
    historical_error = guided_crawl_result.historical_error

    result.historical_links_found = !!historical_result
    has_guided_succeeded_before = db
      .exec_params("select count(*) from guided_successes where start_link_id = $1", [start_link_id])
      .first["count"]
      .to_i == 1
    unless historical_result
      if gt_row
        result.historical_links_pattern_status = :failure
        result.historical_links_pattern = "(#{gt_row["pattern"]})"
        result.historical_links_count_status = :failure
        result.historical_links_count = "(#{gt_row["entries_count"]})"
        result.main_url_status = :failure
        result.main_url = "(#{gt_row["main_page_canonical_url"]})"
        result.oldest_link_status = :failure
        result.oldest_link = "(#{gt_row["oldest_entry_canonical_url"]})"
        if has_guided_succeeded_before
          result.no_guided_regression = false
          result.no_guided_regression_status = :failure
        end
      end
      raise historical_error if historical_error
      raise "Historical links not found"
    end

    entries_count = historical_result.links.length
    oldest_link = historical_result.links.last
    logger.info("Historical links: #{entries_count}")
    historical_result.links.each do |historical_link|
      logger.info("#{historical_link.title} (#{historical_link.url})")
    end
    result.historical_links_titles_matching = guided_crawl_result.feed_result.feed_matching_titles
    result.historical_links_titles_matching_status =
      guided_crawl_result.feed_result.feed_matching_titles_status

    db.exec_params(
      "insert into historical "\
      "(start_link_id, pattern, entries_count, main_page_canonical_url, oldest_entry_canonical_url) "\
      "values "\
      "($1, $2, $3, $4, $5)",
      [
        start_link_id, historical_result.pattern, entries_count, historical_result.main_link.curi.to_s,
        oldest_link.curi.to_s
      ]
    )

    if gt_row
      historical_links_matching = true

      if historical_result.pattern == gt_row["pattern"]
        result.historical_links_pattern_status = :success
        result.historical_links_pattern = historical_result.pattern
      else
        result.historical_links_pattern_status = :failure
        result.historical_links_pattern = "#{historical_result.pattern}<br>(#{gt_row["pattern"]})"
        historical_links_matching = false
      end

      gt_entries_count = gt_row["entries_count"].to_i
      if gt_entries_count != entries_count
        historical_links_matching = false
        result.historical_links_count_status = :failure
        result.historical_links_count = "#{entries_count} (#{gt_entries_count})"
      else
        result.historical_links_count_status = :success
        result.historical_links_count = entries_count
      end

      # Main page url is compared as FYI but doesn't affect status
      gt_main_url = gt_row["main_page_canonical_url"]
      if gt_main_url == historical_result.main_link.curi.to_s
        result.main_url = "<a href=\"#{historical_result.main_link.url}\">#{historical_result.main_link.curi.to_s}</a>"
      else
        result.main_url = "<a href=\"#{historical_result.main_link.url}\">#{historical_result.main_link.curi.to_s}</a><br>(#{gt_row["main_page_canonical_url"]})"
      end

      gt_oldest_curi = CanonicalUri.from_db_string(gt_row["oldest_entry_canonical_url"])
      if !canonical_uri_equal?(gt_oldest_curi, oldest_link.curi, guided_crawl_result.curi_eq_cfg)
        historical_links_matching = false
        result.oldest_link_status = :failure
        result.oldest_link = "<a href=\"#{oldest_link.url}\">#{oldest_link.curi}</a><br>(#{gt_oldest_curi})"
      else
        result.oldest_link_status = :success
        result.oldest_link = "<a href=\"#{oldest_link.url}\">#{oldest_link.curi}</a>"
      end

      result.historical_links_matching = historical_links_matching

      if has_guided_succeeded_before
        result.no_guided_regression = historical_links_matching
        result.no_guided_regression_status = historical_links_matching ? :success : :failure
      elsif historical_links_matching && save_successes
        db.exec_params(
          "insert into guided_successes (start_link_id, timestamp) values ($1, now())", [start_link_id]
        )
        logger.info("Saved guided success")
      end
    else
      result.historical_links_matching = '?'
      result.historical_links_matching_status = :neutral
      result.no_guided_regression_status = :neutral
      result.historical_links_pattern = historical_result.pattern
      result.historical_links_count = entries_count
      result.main_url = "<a href=\"#{historical_result.main_link.url}\">#{historical_result.main_link.curi.to_s}</a>"
      result.oldest_link = "<a href=\"#{oldest_link.url}\">#{oldest_link.curi}</a>"
    end

    result.extra = historical_result.extra

    result
  rescue => e
    raise RunError.new(e.message, result), e
  ensure
    result.duplicate_fetches = crawl_ctx.duplicate_fetches
    result.total_requests = crawl_ctx.requests_made + crawl_ctx.puppeteer_requests_made
    result.total_pages = crawl_ctx.fetched_curis.length
    result.total_network_requests =
      ((defined?(mock_http_client) && mock_http_client && mock_http_client.network_requests_made) || 0) +
        crawl_ctx.puppeteer_requests_made
    result.title_requests = crawl_ctx.title_requests_made
    result.total_time = (monotonic_now - start_time).to_i
  end
end
