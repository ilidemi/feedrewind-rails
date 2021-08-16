require_relative 'canonical_link'
require_relative 'crawling'
require_relative 'crawling_storage'
require_relative 'feed_parsing'
require_relative 'historical_archives'
require_relative 'historical_archives_categories'
require_relative 'historical_archives_sort'
require_relative 'historical_common'
require_relative 'historical_paged'
require_relative 'http_client'
require_relative 'page_parsing'
require_relative 'puppeteer_client'
require_relative 'run_common'
require_relative 'structs'
require_relative 'util'

GUIDED_CRAWLING_RESULT_COLUMNS = [
  [:start_url, :neutral],
  [:comment, :neutral],
  [:gt_pattern, :neutral],
  [:feed_requests_made, :neutral],
  [:feed_time, :neutral],
  [:feed_url, :boolean],
  [:feed_links, :boolean],
  [:duplicate_fetches, :neutral],
  [:no_regression, :neutral],
  [:no_guided_regression, :neutral],
  [:historical_links_found, :boolean],
  [:is_start_page_main_page, :neutral],
  [:does_start_page_link_to_main_page, :neutral],
  [:is_main_page_linked_from_both_entries, :neutral],
  [:unique_links_from_both_entries, :neutral],
  [:historical_links_matching, :boolean],
  [:historical_links_pattern, :neutral_present],
  [:historical_links_count, :neutral_present],
  [:main_url, :neutral_present],
  [:oldest_link, :neutral_present],
  [:extra, :neutral],
  [:total_requests, :neutral],
  [:total_pages, :neutral],
  [:total_network_requests, :neutral],
  [:total_time, :neutral]
]

class GuidedCrawlRunnable
  def initialize
    @result_column_names = to_column_names(GUIDED_CRAWLING_RESULT_COLUMNS)
  end

  def run(start_link_id, save_successes, allow_puppeteer, db, logger)
    guided_crawl(start_link_id, save_successes, allow_puppeteer, db, logger)
  end

  attr_reader :result_column_names
end

HistoricalResult = Struct.new(
  :main_canonical_url, :main_fetch_url, :pattern, :links, :extra, keyword_init: true
)

def guided_crawl(start_link_id, save_successes, allow_puppeteer, db, logger)
  start_link_row = db.exec_params('select url, rss_url from start_links where id = $1', [start_link_id])[0]
  start_link_url = start_link_row["url"]
  start_link_feed_url = start_link_row["rss_url"]
  result = RunResult.new(GUIDED_CRAWLING_RESULT_COLUMNS)
  result.start_url = "<a href=\"#{start_link_url}\">#{start_link_url}</a>"
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
        logger.log("Emptying mock pages and redirects to rerun puppeteer")
        db.exec_params("delete from mock_pages where start_link_id = $1", [start_link_id])
        db.exec_params("delete from mock_redirects where start_link_id = $1", [start_link_id])
      end
    end

    gt_row = db.exec_params(
      "select pattern, entries_count, main_page_canonical_url, oldest_entry_canonical_url from historical_ground_truth where start_link_id = $1",
      [start_link_id]
    ).first
    if gt_row
      result.gt_pattern = gt_row["pattern"]
    end

    mock_http_client = MockJitHttpClient.new(db, start_link_id)
    if allow_puppeteer
      puppeteer_client = PuppeteerClient.new
    else
      puppeteer_client = MockPuppeteerClient.new(db, start_link_id)
    end
    mock_db_storage = GuidedCrawlMockDbStorage.new(db, start_link_id)
    db.exec_params('delete from feeds where start_link_id = $1', [start_link_id])
    db.exec_params('delete from pages where start_link_id = $1', [start_link_id])
    db.exec_params('delete from permanent_errors where start_link_id = $1', [start_link_id])
    db.exec_params('delete from redirects where start_link_id = $1', [start_link_id])
    db.exec_params('delete from historical where start_link_id = $1', [start_link_id])
    db_storage = CrawlDbStorage.new(db, mock_db_storage)

    start_link = to_canonical_link(start_link_url, logger)
    raise "Bad start link: #{start_link_url}" if start_link.nil?

    crawl_ctx.allowed_hosts << start_link.uri.host
    start_result = crawl_request(
      start_link, crawl_ctx, mock_http_client, puppeteer_client, false, start_link_id,
      db_storage, logger
    )
    raise "Unexpected start result: #{start_result}" unless start_result.is_a?(Page) && start_result.content
    start_page = start_result

    feed_start_time = monotonic_now
    if start_link_feed_url
      feed_link = to_canonical_link(start_link_feed_url, logger)
      raise "Bad feed link: #{start_link_feed_url}" if feed_link.nil?
    else
      crawl_ctx.seen_fetch_urls << start_result.fetch_uri.to_s
      feed_links = start_page
        .document
        .xpath("/html/head/link[@rel='alternate']")
        .to_a
        .filter { |link| %w[application/rss+xml application/atom+xml].include?(link.attributes["type"]&.value) }
        .map { |link| link.attributes["href"]&.value }
        .map { |url| to_canonical_link(url, logger, start_link.uri) }
        .filter { |link| !link.url.end_with?("?alt=rss") }
        .filter { |link| !link.url.end_with?("/comments/feed/") }
      raise "No feed links for id #{start_link_id} (#{start_page.fetch_uri})" if feed_links.empty?
      raise "Multiple feed links for id #{start_link_id} (#{start_page.fetch_uri})" if feed_links.length > 1

      feed_link = feed_links.first
    end
    result.feed_url = "<a href=\"#{feed_link.url}\">feed</a>"
    crawl_ctx.allowed_hosts << feed_link.uri.host
    feed_result = crawl_request(
      feed_link, crawl_ctx, mock_http_client, nil, true, start_link_id,
      db_storage, logger
    )
    raise "Unexpected feed result: #{feed_result}" unless feed_result.is_a?(Page) && feed_result.content

    feed_page = feed_result
    crawl_ctx.seen_fetch_urls << feed_page.fetch_uri.to_s
    db_storage.save_feed(start_link_id, feed_page.curi.to_s)
    result.feed_requests_made = crawl_ctx.requests_made
    result.feed_time = (monotonic_now - feed_start_time).to_i
    logger.log("Feed url: #{feed_page.curi}")

    feed_links = extract_feed_links(feed_page.content, feed_page.fetch_uri, logger)
    result.feed_links = feed_links.entry_links.length
    logger.log("Root url: #{feed_links.root_link}")
    logger.log("Entries in feed: #{feed_links.entry_links.length}")
    logger.log("Feed order is certain: #{feed_links.entry_links.is_order_certain}")

    feed_entry_links_by_host = {}
    if feed_links.root_link
      crawl_ctx.allowed_hosts << feed_links.root_link.uri.host
    end
    feed_links.entry_links.to_a.each do |entry_link|
      crawl_ctx.allowed_hosts << entry_link.uri.host

      unless feed_entry_links_by_host.key?(entry_link.uri.host)
        feed_entry_links_by_host[entry_link.uri.host] = []
      end
      feed_entry_links_by_host[entry_link.uri.host] << entry_link
    end

    same_hosts = Set.new
    [[start_link, start_page], [feed_link, feed_page]].each do |link, page|
      if canonical_uri_same_path?(link.curi, page.curi) &&
        (feed_entry_links_by_host.key?(link.uri.host) || feed_entry_links_by_host.key?(page.fetch_uri.host))

        same_hosts << link.uri.host << page.fetch_uri.host
      end
    end

    unless feed_entry_links_by_host.keys.any? { |entry_host| same_hosts.include?(entry_host) }
      entry_link_from_popular_host = feed_entry_links_by_host
        .max { |host_links1, host_links2| host_links2[1].length <=> host_links1[1].length }
        .last
        .first
      entry_result = crawl_request(
        entry_link_from_popular_host, crawl_ctx, mock_http_client, puppeteer_client, false,
        start_link_id, db_storage, logger
      )

      unless entry_result.is_a?(Page) && entry_result.content
        raise "Unexpected entry result: #{entry_result}"
      end

      if canonical_uri_same_path?(entry_link_from_popular_host.curi, entry_result.curi)
        same_hosts << entry_link_from_popular_host.uri.host << entry_result.fetch_uri.host
      end
    end

    curi_eq_cfg = CanonicalEqualityConfig.new(same_hosts, feed_links.generator == :tumblr)
    crawl_ctx.fetched_curis.update_equality_config(curi_eq_cfg)
    crawl_ctx.pptr_fetched_curis.update_equality_config(curi_eq_cfg)
    gt_main_page_curi = CanonicalUri.from_db_string(
      gt_row ? gt_row["main_page_canonical_url"] : "no-ground-truth.com"
    )

    if feed_links.entry_links.length >= 51
      logger.log("Feed is long with #{feed_links.entry_links.length} entries")
      historical_result_combo = {
        best_result: HistoricalResult.new(
          main_canonical_url: feed_page.curi.to_s,
          main_fetch_url: feed_page.fetch_uri.to_s,
          pattern: "long_feed",
          links: feed_links.entry_links.to_a,
          extra: ""
        )
      }
    else
      historical_result_combo = guided_crawl_loop(
        start_link_id, start_page, feed_links.entry_links, feed_links.generator, crawl_ctx, curi_eq_cfg,
        mock_http_client, puppeteer_client, db_storage, gt_main_page_curi, logger
      )
    end

    historical_result = historical_result_combo[:best_result]
    result.historical_links_found = !!historical_result
    result.is_start_page_main_page = historical_result_combo[:is_start_page_main_page]
    result.does_start_page_link_to_main_page = historical_result_combo[:does_start_page_link_to_main_page]
    result.is_main_page_linked_from_both_entries = historical_result_combo[:is_main_page_linked_from_both_entries]
    result.unique_links_from_both_entries = historical_result_combo[:unique_links_from_both_entries]
    has_succeeded_before = db
      .exec_params("select count(*) from successes where start_link_id = $1", [start_link_id])
      .first["count"]
      .to_i == 1
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
        if has_succeeded_before
          result.no_regression = false
          result.no_regression_status = :failure
        end
        if has_guided_succeeded_before
          result.no_guided_regression = false
          result.no_guided_regression_status = :failure
        end
      end
      raise "Historical links not found"
    end

    entries_count = historical_result.links.length
    oldest_link = historical_result.links.last
    logger.log("Historical links: #{entries_count}")
    historical_result.links.each do |historical_link|
      logger.log(historical_link.url)
    end

    db.exec_params(
      "insert into historical "\
      "(start_link_id, pattern, entries_count, main_page_canonical_url, oldest_entry_canonical_url) "\
      "values "\
      "($1, $2, $3, $4, $5)",
      [
        start_link_id, historical_result.pattern, entries_count, historical_result.main_canonical_url,
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

      # TODO: Skipping the check for the main page url for now
      gt_main_url = gt_row["main_page_canonical_url"]
      if gt_main_url == historical_result.main_canonical_url
        result.main_url = "<a href=\"#{historical_result.main_fetch_url}\">#{historical_result.main_canonical_url}</a>"
      else
        result.main_url = "<a href=\"#{historical_result.main_fetch_url}\">#{historical_result.main_canonical_url}</a><br>(#{gt_row["main_page_canonical_url"]})"
      end

      gt_oldest_curi = CanonicalUri.from_db_string(gt_row["oldest_entry_canonical_url"])
      if !canonical_uri_equal?(gt_oldest_curi, oldest_link.curi, curi_eq_cfg)
        historical_links_matching = false
        result.oldest_link_status = :failure
        result.oldest_link = "<a href=\"#{oldest_link.url}\">#{oldest_link.curi}</a><br>(#{gt_oldest_curi})"
      else
        result.oldest_link_status = :success
        result.oldest_link = "<a href=\"#{oldest_link.url}\">#{oldest_link.curi}</a>"
      end

      result.historical_links_matching = historical_links_matching

      if has_succeeded_before
        result.no_regression = historical_links_matching
        result.no_regression_status = historical_links_matching ? :success : :failure
      end
      if has_guided_succeeded_before
        result.no_guided_regression = historical_links_matching
        result.no_guided_regression_status = historical_links_matching ? :success : :failure
      elsif historical_links_matching && save_successes
        db.exec_params(
          "insert into guided_successes (start_link_id, timestamp) values ($1, now())", [start_link_id]
        )
        logger.log("Saved guided success")
      end
    else
      result.historical_links_matching = '?'
      result.historical_links_matching_status = :neutral
      result.no_regression_status = :neutral
      result.no_guided_regression_status = :neutral
      result.historical_links_pattern = historical_result.pattern
      result.historical_links_count = entries_count
      result.main_url = "<a href=\"#{historical_result.main_fetch_url}\">#{historical_result.main_canonical_url}</a>"
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
    result.total_time = (monotonic_now - start_time).to_i
  end
end

ARCHIVES_REGEX = "/(?:archives?|posts?|all)(?:\\.[a-z]+)?/*$"
MAIN_PAGE_REGEX = "/(?:blog|articles|writing|journal)(?:\\.[a-z]+)?/*$"

def guided_crawl_loop(
  start_link_id, start_page, feed_entry_links, feed_generator, crawl_ctx, curi_eq_cfg, mock_http_client,
  puppeteer_client, db_storage, gt_main_page_curi, logger
)
  allowed_hosts = curi_eq_cfg.same_hosts.empty? ?
    [start_page.curi.host] :
    curi_eq_cfg.same_hosts

  start_page_all_links = extract_links(
    start_page, nil, crawl_ctx.redirects, logger, true, true
  )
  start_page_allowed_hosts_links = start_page_all_links
    .filter { |link| allowed_hosts.include?(link.uri.host) }

  start_page_all_curis_set = start_page_all_links
    .map(&:curi)
    .to_canonical_uri_set(curi_eq_cfg)
  feed_entry_curis_set = feed_entry_links
    .to_a
    .map(&:curi)
    .to_canonical_uri_set(curi_eq_cfg)
  archives_categories_state = ArchivesCategoriesState.new
  pages_without_puppeteer = []

  does_start_page_path_match_archives = start_page.curi.path.match?(ARCHIVES_REGEX)
  if does_start_page_path_match_archives
    result = try_extract_historical(
      start_page, start_page_all_links, start_page_all_curis_set, feed_entry_links, feed_entry_curis_set,
      feed_generator, curi_eq_cfg, start_link_id, crawl_ctx, mock_http_client, db_storage,
      archives_categories_state, logger
    )
    return result if result

    logger.log("Start page matches archives regex but is not the main page")
    pages_without_puppeteer << start_page unless start_page.is_puppeteer_used
  else
    logger.log("Start page doesn't match archives regex")
  end

  logger.log("Trying select links from start page")

  start_page_archives_links = start_page_allowed_hosts_links
    .filter { |link| link.curi.path.match?(ARCHIVES_REGEX) }
  unless start_page_archives_links.empty?
    logger.log("Checking #{start_page_archives_links.length} archives links")
    result, start_page_archives_pages_without_puppeteer = crawl_historical(
      start_page_archives_links, feed_entry_links, feed_entry_curis_set, feed_generator, curi_eq_cfg,
      start_link_id, crawl_ctx, mock_http_client, puppeteer_client, db_storage, archives_categories_state,
      logger
    )
    return result if result

    pages_without_puppeteer.push(*start_page_archives_pages_without_puppeteer)
  end
  logger.log("Start page doesn't link to archives")

  unless does_start_page_path_match_archives
    result = try_extract_historical(
      start_page, start_page_all_links, start_page_all_curis_set, feed_entry_links, feed_entry_curis_set,
      feed_generator, curi_eq_cfg, start_link_id, crawl_ctx, mock_http_client, db_storage,
      archives_categories_state, logger
    )
    return result if result

    logger.log("Start page is not the main page")
    pages_without_puppeteer << start_page unless start_page.is_puppeteer_used
  end

  start_page_main_page_links, start_page_other_page_links = start_page_allowed_hosts_links.partition do |link|
    allowed_hosts.include?(link.uri.host) && link.curi.path.match?(MAIN_PAGE_REGEX)
  end
  unless start_page_main_page_links.empty?
    logger.log("Checking #{start_page_main_page_links.length} main page links")
    result, start_page_main_pages_without_puppeteer = crawl_historical(
      start_page_main_page_links, feed_entry_links, feed_entry_curis_set, feed_generator, curi_eq_cfg,
      start_link_id, crawl_ctx, mock_http_client, puppeteer_client, db_storage, archives_categories_state,
      logger
    )
    return result if result

    pages_without_puppeteer.push(*start_page_main_pages_without_puppeteer)
  end
  logger.log("Start page doesn't link to the main page")

  logger.log("Trying common links from the first two entries")

  raise "Too few entries in feed: #{feed_entry_links.length}" if feed_entry_links.length < 2
  feed_entry_links_arr = feed_entry_links.to_a
  entry1_page = crawl_request(
    feed_entry_links_arr[0], crawl_ctx, mock_http_client, nil, false,
    start_link_id, db_storage, logger
  )
  entry2_page = crawl_request(
    feed_entry_links_arr[1], crawl_ctx, mock_http_client, nil, false,
    start_link_id, db_storage, logger
  )
  raise "Couldn't fetch entry 1: #{entry1_page}" unless entry1_page.is_a?(Page) && entry1_page.document
  raise "Couldn't fetch entry 2: #{entry2_page}" unless entry2_page.is_a?(Page) && entry2_page.document

  entry1_links = extract_links(
    entry1_page, allowed_hosts, crawl_ctx.redirects, logger, true, true
  )
  entry2_links = extract_links(
    entry2_page, allowed_hosts, crawl_ctx.redirects, logger, true, true
  )
  entry1_curis_set = entry1_links
    .map(&:curi)
    .to_canonical_uri_set(curi_eq_cfg)
  entry2_curis_set = entry2_links
    .map(&:curi)
    .to_canonical_uri_set(curi_eq_cfg)

  links_from_both_entries = []
  entry1_curis_set2 = CanonicalUriSet.new([], curi_eq_cfg)
  entry1_links.each do |entry1_link|
    next if entry1_curis_set2.include?(entry1_link.curi)

    entry1_curis_set2 << entry1_link.curi
    links_from_both_entries << entry1_link if entry2_curis_set.include?(entry1_link.curi)
  end

  archives_links_from_both_entries, non_archives_links_from_both_entries = links_from_both_entries
    .partition { |link| link.curi.path.match?(ARCHIVES_REGEX) }
  unless archives_links_from_both_entries.empty?
    logger.log("Checking #{archives_links_from_both_entries.length} archives links")
    result, archives_pages_without_puppeteer_from_both_entries = crawl_historical(
      archives_links_from_both_entries, feed_entry_links, feed_entry_curis_set, feed_generator, curi_eq_cfg,
      start_link_id, crawl_ctx, mock_http_client, puppeteer_client, db_storage, archives_categories_state,
      logger
    )
    return result if result

    pages_without_puppeteer.push(*archives_pages_without_puppeteer_from_both_entries)
  end
  logger.log("First two entries don't link to archives")

  main_page_links_from_both_entries, other_links_from_both_entries = non_archives_links_from_both_entries
    .partition { |link| link.curi.path.match?(MAIN_PAGE_REGEX) }
  unless main_page_links_from_both_entries.empty?
    logger.log("Checking #{main_page_links_from_both_entries.length} main page links")
    result, main_pages_without_puppeteer_from_both_entries = crawl_historical(
      main_page_links_from_both_entries, feed_entry_links, feed_entry_curis_set, feed_generator, curi_eq_cfg,
      start_link_id, crawl_ctx, mock_http_client, puppeteer_client, db_storage, archives_categories_state,
      logger
    )
    return result if result

    pages_without_puppeteer.push(*main_pages_without_puppeteer_from_both_entries)
  end
  logger.log("First two entries don't link to the main page")

  other_non_entry_links_from_both_entries = other_links_from_both_entries
    .filter { |link| !feed_entry_curis_set.include?(link.curi) }
  if other_non_entry_links_from_both_entries.length > 10
    filtered_other_non_entry_links_from_both_entries =
      filter_top_level_non_year_links(other_non_entry_links_from_both_entries)
    logger.log("Filtering #{other_non_entry_links_from_both_entries.length} other non-entry links to #{filtered_other_non_entry_links_from_both_entries.length}")
  else
    filtered_other_non_entry_links_from_both_entries = other_non_entry_links_from_both_entries
  end

  unless filtered_other_non_entry_links_from_both_entries.empty?
    logger.log("Checking #{filtered_other_non_entry_links_from_both_entries.length} other non-entry links")
    # Don't use puppeteer for these links
    result, _ = crawl_historical(
      filtered_other_non_entry_links_from_both_entries, feed_entry_links, feed_entry_curis_set,
      feed_generator, curi_eq_cfg, start_link_id, crawl_ctx, mock_http_client, nil, db_storage,
      archives_categories_state, logger
    )
    return result if result
  end

  logger.log("First two entries don't link to something with a pattern")

  logger.log("Trying filtered other links from the start page")
  start_page_filtered_other_links = filter_top_level_non_year_links(start_page_other_page_links)
  are_any_feed_entries_top_level = feed_entry_links
    .to_a
    .any? { |entry_link| [nil, 1].include?(entry_link.curi.trimmed_path&.count("/")) }
  if !start_page_filtered_other_links.empty? && !are_any_feed_entries_top_level
    # Don't use puppeteer for these links
    result, _ = crawl_historical(
      start_page_filtered_other_links, feed_entry_links, feed_entry_curis_set, feed_generator, curi_eq_cfg,
      start_link_id, crawl_ctx, mock_http_client, nil, db_storage, archives_categories_state,
      logger
    )
    return result if result
  end
  logger.log("Start page doesn't link to something with a pattern")

  logger.log("Retrying #{pages_without_puppeteer.length} pages with Puppeteer")
  pages_without_puppeteer.each_with_index do |page, index|
    logger.log("#{index + 1}/#{pages_without_puppeteer.length} #{page.curi}")
    content, document = puppeteer_client.fetch(page.fetch_uri.to_s, crawl_ctx, logger)
    page_from_puppeteer = Page.new(
      page.curi, page.fetch_uri, page.start_link_id, page.content_type, content, document, true
    )

    if !crawl_ctx.pptr_fetched_curis.include?(page.curi)
      crawl_ctx.pptr_fetched_curis << page.curi
      db_storage.save_page(
        page.curi.to_s, page.fetch_uri.to_s, page.content_type, start_link_id, content, true
      )
      logger.log("Puppeteer page saved")
    else
      logger.log("Puppeteer page saved - canonical uri already seen")
    end

    page_from_puppeteer_links = extract_links(
      page_from_puppeteer, nil, crawl_ctx.redirects, logger, true,
      true
    )
    page_from_puppeteer_curis_set = page_from_puppeteer_links
      .map(&:curi)
      .to_canonical_uri_set(curi_eq_cfg)
    result = try_extract_historical(
      page_from_puppeteer, page_from_puppeteer_links, page_from_puppeteer_curis_set, feed_entry_links,
      feed_entry_curis_set, feed_generator, curi_eq_cfg, start_link_id, crawl_ctx, mock_http_client,
      db_storage, archives_categories_state, logger
    )
    return result if result
  end

  logger.log("Pattern not detected")

  # STATS
  is_start_page_main_page = canonical_uri_equal?(start_page.curi, gt_main_page_curi, curi_eq_cfg)
  does_start_page_link_to_main_page = start_page_all_curis_set.include?(gt_main_page_curi)
  is_main_page_linked_from_both_entries =
    entry1_curis_set.include?(gt_main_page_curi) && entry2_curis_set.include?(gt_main_page_curi)

  unless is_start_page_main_page || does_start_page_link_to_main_page
    logger.log("Would need to crawl #{links_from_both_entries.length} links common for two entries:")
    links_from_both_entries.each do |link|
      logger.log(link.curi.to_s)
    end
  end
  # STATS END

  {
    is_start_page_main_page: is_start_page_main_page,
    does_start_page_link_to_main_page: does_start_page_link_to_main_page,
    is_main_page_linked_from_both_entries: is_main_page_linked_from_both_entries,
    unique_links_from_both_entries: links_from_both_entries.length,
    best_result: nil
  }
end

def crawl_historical(
  links, feed_entry_links, feed_entry_curis_set, feed_generator, curi_eq_cfg, start_link_id, crawl_ctx,
  mock_http_client, puppeteer_client, db_storage, archives_categories_state, logger
)
  pages_without_puppeteer = []
  links.each do |link|
    next if crawl_ctx.fetched_curis.include?(link.curi)

    link_page = crawl_request(
      link, crawl_ctx, mock_http_client, puppeteer_client, false, start_link_id, db_storage,
      logger
    )
    unless link_page.is_a?(Page) && link_page.document
      logger.log("Couldn't fetch link: #{link_page}")
      next
    end
    pages_without_puppeteer << link_page unless link_page.is_puppeteer_used

    link_page_links = extract_links(
      link_page, nil, crawl_ctx.redirects, logger, true, true
    )
    link_page_curis_set = link_page_links
      .map(&:curi)
      .to_canonical_uri_set(curi_eq_cfg)
    link_result = try_extract_historical(
      link_page, link_page_links, link_page_curis_set, feed_entry_links, feed_entry_curis_set, feed_generator,
      curi_eq_cfg, start_link_id, crawl_ctx, mock_http_client, db_storage, archives_categories_state, logger
    )

    return [link_result, []] if link_result
  end

  [nil, pages_without_puppeteer]
end

def try_extract_historical(
  page, page_links, page_curis_set, feed_entry_links, feed_entry_curis_set, feed_generator, curi_eq_cfg,
  start_link_id, crawl_ctx, mock_http_client, db_storage, archives_categories_state, logger
)
  logger.log("Trying to extract historical from #{page.fetch_uri}")

  archives_almost_match_threshold = get_archives_almost_match_threshold(feed_entry_links.length)
  extractions_by_masked_xpath_by_star_count = get_extractions_by_masked_xpath_by_star_count(
    page_links, feed_entry_links, feed_entry_curis_set, curi_eq_cfg, archives_almost_match_threshold, logger
  )

  archives_result = try_extract_archives(
    page, page_links, page_curis_set, feed_entry_links, feed_entry_curis_set, feed_generator,
    extractions_by_masked_xpath_by_star_count, archives_almost_match_threshold, curi_eq_cfg, logger
  )

  archives_categories_result = try_extract_archives_categories(
    page, page_curis_set, feed_entry_links, feed_entry_curis_set, extractions_by_masked_xpath_by_star_count,
    archives_categories_state, curi_eq_cfg, logger
  )

  page1_result = try_extract_page1(
    page, page_links, page_curis_set, feed_entry_links, feed_entry_curis_set, feed_generator, curi_eq_cfg,
    logger
  )

  paged_result = nil
  if page1_result
    page2 = crawl_request(
      page1_result.link_to_page2, crawl_ctx, mock_http_client, nil, false, start_link_id, db_storage, logger
    )
    if page2 && page2.is_a?(Page) && page2.document
      paged_result = try_extract_page2(
        page2, page1_result.paged_state, feed_entry_links, curi_eq_cfg, logger
      )
    else
      logger.log("Page 2 is not a page: #{page2}")
    end
  end

  result = nil
  if archives_result
    result = archives_result
  end
  if archives_categories_result &&
    (!result || !result.count || archives_categories_result.count > result.count)

    result = archives_categories_result
  end
  if paged_result &&
    (
      !result || !result.count || paged_result.count > result.count ||
        (paged_result.is_a?(PartialPagedResult) && paged_result.count == result.count)
    )
    result = paged_result
  end

  return nil unless result

  if result.is_a?(ArchivesResult)
    postprocessed_result = postprocess_archives_result(
      result, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, start_link_id, db_storage, logger
    )
  elsif result.is_a?(ArchivesCategoriesResult)
    postprocessed_result = postprocess_archives_categories_result(
      result, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, start_link_id, db_storage, logger
    )
  elsif result.is_a?(PagedResult) || result.is_a?(PartialPagedResult)
    postprocessed_result = postprocess_paged_result(
      result, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, start_link_id, db_storage, logger
    )
  else
    raise "Unknown result type: #{result}"
  end

  unless postprocessed_result
    logger.log("Postprocessing failed for this page")
    return nil
  end

  {
    best_result: HistoricalResult.new(
      main_canonical_url: page.curi.to_s,
      main_fetch_url: page.fetch_uri.to_s,
      pattern: postprocessed_result.pattern,
      links: postprocessed_result.links,
      extra: postprocessed_result.extra
    )
  }
end

PostprocessedResult = Struct.new(:pattern, :links, :extra, keyword_init: true)

def postprocess_archives_result(
  archives_result, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, start_link_id, db_storage, logger
)
  if archives_result.main_result.is_a?(MediumWithPinnedEntryResult)
    medium_result = archives_result.main_result
    pinned_entry_page = crawl_request(
      medium_result.pinned_entry_link, crawl_ctx, mock_http_client, nil, false,
      start_link_id, db_storage, logger
    )
    unless pinned_entry_page.is_a?(Page) && pinned_entry_page.document
      logger.log("Couldn't fetch first Medium link during result postprocess: #{pinned_entry_page}")
      return nil
    end

    pinned_entry_page_links = extract_links(
      pinned_entry_page, [pinned_entry_page.fetch_uri.host], crawl_ctx.redirects, logger
    )

    sorted_links = historical_archives_medium_sort_finish(
      medium_result.pinned_entry_link, pinned_entry_page_links, medium_result.other_links_dates, curi_eq_cfg
    )
    unless sorted_links
      logger.log("Couldn't sort links during result postprocess")
      return nil
    end

    return nil unless compare_with_feed(sorted_links, feed_entry_links, curi_eq_cfg, logger)

    return PostprocessedResult.new(
      pattern: medium_result.pattern,
      links: sorted_links,
      extra: medium_result.extra
    )
  end

  best_result = archives_result.main_result

  if archives_result.tentative_better_results
    pages_by_canonical_url = {}
    sorted_tentative_results = archives_result
      .tentative_better_results.sort_by { |tentative_result| tentative_result.count }

    sorted_tentative_results.each do |tentative_result|
      sorted_links = postprocess_sort_links_maybe_dates(
        tentative_result.links_maybe_dates, feed_entry_links, curi_eq_cfg, pages_by_canonical_url, crawl_ctx,
        mock_http_client, start_link_id, db_storage, logger
      )
      return best_result unless sorted_links

      best_result = PostprocessedResult.new(
        pattern: tentative_result.pattern,
        links: sorted_links,
        extra: tentative_result.extra
      )
    end
  end

  best_result
end

def postprocess_archives_categories_result(
  archives_categories_result, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, start_link_id,
  db_storage, logger
)
  sorted_links = postprocess_sort_links_maybe_dates(
    archives_categories_result.links_maybe_dates, feed_entry_links, curi_eq_cfg, {}, crawl_ctx,
    mock_http_client, start_link_id, db_storage, logger
  )
  return nil unless sorted_links

  PostprocessedResult.new(
    pattern: archives_categories_result.pattern,
    links: sorted_links,
    extra: archives_categories_result.extra
  )
end

def postprocess_paged_result(
  paged_result, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, start_link_id, db_storage, logger
)
  while paged_result.is_a?(PartialPagedResult)
    page = crawl_request(
      paged_result.link_to_next_page, crawl_ctx, mock_http_client, nil, false, start_link_id, db_storage,
      logger
    )
    unless page && page.is_a?(Page) && page.document
      logger.log("Page #{paged_result.page_number} is not a page: #{page}")
      return nil
    end

    paged_result = try_extract_next_page(
      page, paged_result.paged_state, feed_entry_links, curi_eq_cfg, logger
    )
  end

  paged_result
end

def postprocess_sort_links_maybe_dates(
  links_maybe_dates, feed_entry_links, curi_eq_cfg, pages_by_canonical_url, crawl_ctx, mock_http_client,
  start_link_id, db_storage, logger
)
  result_pages = []
  sort_state = nil
  links_with_dates, links_without_dates = links_maybe_dates.partition { |_, maybe_date| maybe_date }
  links_without_dates = links_without_dates.map(&:first)
  links_without_dates.each do |link|
    if pages_by_canonical_url.key?(link.curi.to_s)
      page = pages_by_canonical_url[link.curi.to_s]
    else
      page = crawl_request(
        link, crawl_ctx, mock_http_client, nil, false, start_link_id, db_storage,
        logger
      )
      unless page.is_a?(Page) && page.document
        logger.log("Couldn't fetch link during result postprocess: #{page}")
        return nil
      end
    end

    sort_state = historical_archives_sort_add(page, sort_state, logger)
    return nil unless sort_state

    result_pages << page
    pages_by_canonical_url[page.curi.to_s] = page
  end

  sorted_links = historical_archives_sort_finish(
    links_with_dates, links_without_dates, sort_state, logger
  )
  return nil unless sorted_links

  return nil unless compare_with_feed(sorted_links, feed_entry_links, curi_eq_cfg, logger)

  sorted_links
end

def filter_top_level_non_year_links(links)
  links.filter do |link|
    level = link.curi.trimmed_path&.count("/")
    [nil, 1].include?(level) && !link.curi.trimmed_path&.match?(/\/\d+/)
  end
end

def compare_with_feed(sorted_links, feed_entry_links, curi_eq_cfg, logger)
  if feed_entry_links.is_order_certain
    sorted_curis = sorted_links.map(&:curi)
    curis_set = sorted_curis.to_canonical_uri_set(curi_eq_cfg)
    present_feed_entry_links = feed_entry_links.filter_included(curis_set)
    is_matching_feed = present_feed_entry_links.sequence_match?(sorted_curis, curi_eq_cfg)
    unless is_matching_feed
      logger.log("Sorted links")
      logger.log("#{sorted_curis.map(&:to_s)}")
      logger.log("are not matching filtered feed:")
      logger.log(present_feed_entry_links)
      return false
    end
  end

  true
end