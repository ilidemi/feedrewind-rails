require 'pg'
require 'set'
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
  [:historical_links_found, :boolean],
  [:historical_links_matching, :boolean],
  [:historical_links_pattern, :neutral_present],
  [:historical_links_count, :neutral_present],
  [:historical_links_titles_partially_matching, :neutral_present],
  [:historical_links_titles_exactly_matching, :neutral_present],
  [:historical_links_titles_matching_feed, :neutral_present],
  [:no_guided_regression, :neutral],
  [:main_url, :neutral_present],
  [:oldest_link, :neutral_present],
  [:extra, :neutral],
  [:total_requests, :neutral],
  [:total_pages, :neutral],
  [:total_network_requests, :neutral],
  [:duplicate_fetches, :neutral],
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
      "select pattern, entries_count, main_page_canonical_url, oldest_entry_canonical_url, titles, links "\
      "from historical_ground_truth "\
      "where start_link_id = $1",
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

    start_url = start_link_feed_url || start_link_url
    discover_feeds_result = discover_feeds_at_url(start_url, crawl_ctx, mock_http_client, logger)

    if discover_feeds_result == :discovered_bad_feed
      raise "Bad feed at #{start_url}"
    elsif discover_feeds_result.is_a?(DiscoveredSingleFeed)
      discovered_start_page = nil
      discovered_start_feed = discover_feeds_result.feed
    else
      raise "No feeds discovered" if discover_feeds_result.feeds.empty?
      raise "More than one feed discovered" if discover_feeds_result.feeds.length > 1

      discovered_start_page = discover_feeds_result.start_page
      discovered_start_feed = discover_feeds_result.feeds.first
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
      logger.info("#{historical_link.title.value} #{print_title_source(historical_link.title.source)} (#{historical_link.url})")
    end
    result.historical_links_titles_matching_feed = guided_crawl_result.feed_result.feed_matching_titles
    result.historical_links_titles_matching_feed_status =
      guided_crawl_result.feed_result.feed_matching_titles_status

    link_titles = historical_result.links.map(&:title)
    link_curis = historical_result.links.map(&:curi)
    db.exec_params(
      "insert into historical "\
      "(start_link_id, pattern, entries_count, main_page_canonical_url, oldest_entry_canonical_url, titles, links) "\
      "values "\
      "($1, $2, $3, $4, $5, $6::text[], $7::text[])",
      [
        start_link_id, historical_result.pattern, entries_count, historical_result.main_link.curi.to_s,
        oldest_link.curi.to_s, PG::TextEncoder::Array.new.encode(link_titles.map(&:value)),
        PG::TextEncoder::Array.new.encode(link_curis.map(&:to_s))
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
      if gt_row["links"]
        gt_curis = PG::TextDecoder::Array
          .new
          .decode(gt_row["links"])
          .map { |curl| CanonicalUri::from_db_string(curl) }
      else
        gt_curis = nil
      end
      if gt_entries_count != entries_count
        historical_links_matching = false
        result.historical_links_count_status = :failure
        result.historical_links_count = "#{entries_count} (#{gt_entries_count})"
        if gt_curis
          logger.info("Ground truth links:")
          gt_curis.each do |gt_curi|
            logger.info(gt_curi.to_s)
          end
        else
          logger.info("Ground truth links not present")
        end
      else
        if gt_curis
          link_mismatches = link_curis.zip(gt_curis).filter do |curi, gt_curi|
            !canonical_uri_equal?(curi, gt_curi, guided_crawl_result.curi_eq_cfg)
          end
          if link_mismatches.empty?
            result.historical_links_count_status = :success
            result.historical_links_count = entries_count
          else
            historical_links_matching = false
            result.historical_links_count_status = :failure
            result.historical_links_count = "#{entries_count} (uri mismatch: #{link_mismatches.length})"
            logger.info("Historical link mismatches (#{link_mismatches.length}):")
            link_mismatches.each do |curi, gt_curi|
              logger.info("#{curi.to_s} != #{gt_curi.to_s}")
            end
          end
        else
          result.historical_links_count_status = :neutral
        end
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

      if gt_row["titles"]
        gt_titles = PG::TextDecoder::Array
          .new
          .decode(gt_row["titles"])
          .map { |title_value| create_link_title(title_value, :ground_truth) }
      else
        gt_titles = nil
      end
      if gt_titles.nil?
        logger.info("Ground truth titles not present")
        result.historical_links_titles_partially_matching_status = :neutral
        result.historical_links_titles_exactly_matching_status = :neutral
      elsif entries_count == gt_titles.length
        exact_mismatching_titles = link_titles
          .zip(gt_titles)
          .filter { |title, gt_title| title.equalized_value != gt_title.equalized_value }

        if exact_mismatching_titles.empty?
          result.historical_links_titles_partially_matching_status = :success
          result.historical_links_titles_partially_matching = "#{link_titles.length}"
          result.historical_links_titles_exactly_matching_status = :success
          result.historical_links_titles_exactly_matching = "#{link_titles.length}"
        else
          historical_links_matching = false

          partial_mismatching_titles = exact_mismatching_titles.filter do |title, gt_title|
            !title.equalized_value.end_with?(gt_title.equalized_value) &&
              !gt_title.equalized_value.start_with?(title.equalized_value)
          end

          if partial_mismatching_titles.empty?
            result.historical_links_titles_partially_matching_status = :success
            result.historical_links_titles_partially_matching = "#{link_titles.length}"
          else
            result.historical_links_titles_partially_matching_status = :failure
            result.historical_links_titles_partially_matching = "#{gt_titles.length - partial_mismatching_titles.length} (#{gt_titles.length})"
            logger.info("Partially mismatching titles (#{partial_mismatching_titles.length}):")
            partial_mismatching_titles.each do |title, gt_title|
              logger.info("Partial #{print_title(title)} != GT \"#{gt_title.value}\"")
            end
          end

          result.historical_links_titles_exactly_matching_status = :failure
          result.historical_links_titles_exactly_matching = "#{gt_titles.length - exact_mismatching_titles.length} (#{gt_titles.length})"
          logger.info("Exactly mismatching titles (#{exact_mismatching_titles.length}):")
          exact_mismatching_titles.each do |title, gt_title|
            logger.info("Exact #{print_title(title)} != GT \"#{gt_title.value}\"")
          end
        end
      else
        eq_gt_title_values_set = gt_titles.map(&:equalized_value).to_set
        titles_matching_count = link_titles
          .count { |title| eq_gt_title_values_set.include?(title.equalized_value) }
        historical_links_matching = false
        result.historical_links_titles_partially_matching_status = :failure
        result.historical_links_titles_partially_matching = "#{titles_matching_count} (#{gt_titles.length})"
        result.historical_links_titles_exactly_matching_status = :failure
        result.historical_links_titles_exactly_matching = "#{titles_matching_count} (#{gt_titles.length})"
        logger.info("Ground truth titles:")
        gt_titles.each do |gt_title|
          logger.info(gt_title.value)
        end
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
      result.historical_links_titles_partially_matching_status = :neutral
      result.historical_links_titles_exactly_matching_status = :neutral
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
