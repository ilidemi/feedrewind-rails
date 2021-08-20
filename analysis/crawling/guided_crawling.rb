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
  [:source, :neutral],
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

    if start_link_url
      start_link = to_canonical_link(start_link_url, logger)
      raise "Bad start link: #{start_link_url}" if start_link.nil?

      start_result = crawl_request(
        start_link, false, nil, crawl_ctx, mock_http_client, puppeteer_client, start_link_id,
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
          .filter { |link| link }
          .filter { |link| !link.url.end_with?("?alt=rss") }
          .filter { |link| !link.url.end_with?("/comments/feed/") }
          .filter { |link| !link.url.end_with?("/comments/feed") }
        raise "No feed links for id #{start_link_id} (#{start_page.fetch_uri})" if feed_links.empty?
        raise "Multiple feed links for id #{start_link_id} (#{start_page.fetch_uri})" if feed_links.length > 1

        feed_link = feed_links.first
      end

      result.feed_url = "<a href=\"#{feed_link.url}\">feed</a>"
      feed_result = crawl_request(
        feed_link, true, nil, crawl_ctx, mock_http_client, nil, start_link_id, db_storage, logger
      )
      raise "Unexpected feed result: #{feed_result}" unless feed_result.is_a?(Page) && feed_result.content

      feed_page = feed_result
      crawl_ctx.seen_fetch_urls << feed_page.fetch_uri.to_s
      db_storage.save_feed(start_link_id, feed_page.curi.to_s)
      result.feed_requests_made = crawl_ctx.requests_made
      result.feed_time = (monotonic_now - feed_start_time).to_i
      logger.log("Feed url: #{feed_page.curi}")

      feed_links = extract_feed_links(feed_page.content, feed_page.fetch_uri, logger)
    elsif start_link_feed_url
      feed_start_time = monotonic_now
      feed_link = to_canonical_link(start_link_feed_url, logger)
      raise "Bad feed link: #{start_link_feed_url}" if feed_link.nil?

      result.feed_url = "<a href=\"#{feed_link.url}\">feed</a>"
      feed_result = crawl_request(
        feed_link, true, nil, crawl_ctx, mock_http_client, nil, start_link_id, db_storage, logger
      )
      raise "Unexpected feed result: #{feed_result}" unless feed_result.is_a?(Page) && feed_result.content

      feed_page = feed_result
      crawl_ctx.seen_fetch_urls << feed_page.fetch_uri.to_s
      db_storage.save_feed(start_link_id, feed_page.curi.to_s)
      result.feed_requests_made = crawl_ctx.requests_made
      result.feed_time = (monotonic_now - feed_start_time).to_i
      logger.log("Feed url: #{feed_page.curi}")

      feed_links = extract_feed_links(feed_page.content, feed_page.fetch_uri, logger)

      if feed_links.root_link
        start_link = feed_links.root_link

        result.start_url = "<a href=\"#{start_link.url}\">#{start_link.url}</a>"
        start_result = crawl_request(
          start_link, false, nil, crawl_ctx, mock_http_client, puppeteer_client, start_link_id,
          db_storage, logger
        )
        unless start_result.is_a?(Page) && start_result.content
          raise "Unexpected start result: #{start_result}"
        end
        start_page = start_result
      else
        logger.log("There is no start link or feed root link, trying to discover")
        start_link = start_page = nil
        possible_start_uri = feed_link.uri
        loop do
          raise "Couldn't discover start link" if !possible_start_uri.path || possible_start_uri.path.empty?

          possible_start_uri.path = possible_start_uri.path.rpartition("/").first
          possible_start_link = to_canonical_link(possible_start_uri.to_s, logger)
          logger.log("Possible start link: #{possible_start_uri.to_s}")
          possible_start_result = crawl_request(
            possible_start_link, false, nil, crawl_ctx, mock_http_client, puppeteer_client, start_link_id,
            db_storage, logger
          )
          next unless possible_start_result.is_a?(Page) && possible_start_result.content

          start_link = possible_start_link
          start_page = possible_start_result
          break
        end

        result.start_url = "<a href=\"#{start_link.url}\">#{start_link.url}</a>"
      end
    else
      raise "Both url or feed url are not present"
    end

    result.feed_links = feed_links.entry_links.length
    logger.log("Root url: #{feed_links.root_link&.url}")
    logger.log("Entries in feed: #{feed_links.entry_links.length}")
    logger.log("Feed order is certain: #{feed_links.entry_links.is_order_certain}")

    raise "Feed only has 1 item" if feed_links.entry_links.length == 1

    feed_entry_links_by_host = {}
    feed_links.entry_links.to_a.each do |entry_link|
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
        entry_link_from_popular_host, false, nil, crawl_ctx, mock_http_client, nil, start_link_id, db_storage,
        logger
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

    historical_error = nil
    if feed_links.entry_links.length >= 101
      logger.log("Feed is long with #{feed_links.entry_links.length} entries")
      historical_result = HistoricalResult.new(
        main_link: feed_link,
        pattern: "long_feed",
        links: feed_links.entry_links.to_a,
        count: feed_links.entry_links.length,
        extra: ""
      )
    else
      begin
        historical_result = guided_crawl(
          start_link_id, start_page, feed_links.entry_links, feed_links.generator, crawl_ctx, curi_eq_cfg,
          mock_http_client, puppeteer_client, db_storage, logger
        )
      rescue => e
        historical_result = nil
        historical_error = e
      end
    end

    result.historical_links_found = !!historical_result
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
      raise historical_error if historical_error
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

      # TODO: Skipping the check for the main page url for now
      gt_main_url = gt_row["main_page_canonical_url"]
      if gt_main_url == historical_result.main_link.curi.to_s
        result.main_url = "<a href=\"#{historical_result.main_link.url}\">#{historical_result.main_link.curi.to_s}</a>"
      else
        result.main_url = "<a href=\"#{historical_result.main_link.url}\">#{historical_result.main_link.curi.to_s}</a><br>(#{gt_row["main_page_canonical_url"]})"
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
    result.total_time = (monotonic_now - start_time).to_i
  end
end

ARCHIVES_REGEX = "/(?:(?:[a-z]+-)?archives?|posts?|all(?:-[a-z]+)?)(?:\\.[a-z]+)?$"
MAIN_PAGE_REGEX = "/(?:blog|articles|writing|journal|essays)(?:\\.[a-z]+)?$"

HistoricalResult = Struct.new(:main_link, :pattern, :links, :count, :extra, keyword_init: true)

def guided_crawl(
  start_link_id, start_page, feed_entry_links, feed_generator, crawl_ctx, curi_eq_cfg, mock_http_client,
  puppeteer_client, db_storage, logger
)
  archives_queue = []
  main_page_queue = []

  archives_pptr_retry_queue = []
  main_page_pptr_retry_queue = []

  guided_seen_queryless_curis_set = CanonicalUriSet.new([], curi_eq_cfg)

  allowed_hosts = curi_eq_cfg.same_hosts.empty? ?
    [start_page.curi.host] :
    curi_eq_cfg.same_hosts

  start_page_all_links = extract_links(
    start_page.document, start_page.fetch_uri, nil, crawl_ctx.redirects, logger, true, true
  )
  start_page_allowed_hosts_links = start_page_all_links
    .filter { |link| allowed_hosts.include?(link.uri.host) }

  feed_entry_curis_set = feed_entry_links
    .to_a
    .map(&:curi)
    .to_canonical_uri_set(curi_eq_cfg)

  archives_categories_state = ArchivesCategoriesState.new

  if start_page.curi.trimmed_path&.match?(ARCHIVES_REGEX)
    archives_queue << start_page
  else
    main_page_queue << start_page
  end

  start_page_other_links = []
  start_page_allowed_hosts_links.each do |link|
    queryless_curi = canonical_uri_without_query(link.curi)
    next if guided_seen_queryless_curis_set.include?(queryless_curi)

    if link.curi.trimmed_path&.match?(ARCHIVES_REGEX)
      guided_seen_queryless_curis_set << queryless_curi
      archives_queue << link
    elsif link.curi.trimmed_path&.match?(MAIN_PAGE_REGEX)
      guided_seen_queryless_curis_set << queryless_curi
      main_page_queue << link
    else
      start_page_other_links << link
    end
  end

  logger.log("Start page and links: #{archives_queue.length} archives, #{main_page_queue.length} main page")

  result = guided_crawl_loop(
    [archives_queue, main_page_queue], [archives_pptr_retry_queue, main_page_pptr_retry_queue],
    guided_seen_queryless_curis_set, archives_categories_state, feed_entry_links, feed_entry_curis_set,
    feed_generator, curi_eq_cfg, allowed_hosts, crawl_ctx, mock_http_client, puppeteer_client, start_link_id,
    db_storage, logger
  )
  return result if result

  raise "Too few entries in feed: #{feed_entry_links.length}" if feed_entry_links.length < 2
  feed_entry_links_arr = feed_entry_links.to_a
  entry1_page = crawl_request(
    feed_entry_links_arr[0], false, feed_entry_curis_set, crawl_ctx, mock_http_client, nil, start_link_id,
    db_storage, logger
  )
  entry2_page = crawl_request(
    feed_entry_links_arr[1], false, feed_entry_curis_set, crawl_ctx, mock_http_client, nil, start_link_id,
    db_storage, logger
  )
  raise "Couldn't fetch entry 1: #{entry1_page}" unless entry1_page.is_a?(Page) && entry1_page.document
  raise "Couldn't fetch entry 2: #{entry2_page}" unless entry2_page.is_a?(Page) && entry2_page.document

  entry1_links = extract_links(
    entry1_page.document, entry1_page.fetch_uri, allowed_hosts, crawl_ctx.redirects, logger, true, true
  )
  entry2_links = extract_links(
    entry2_page.document, entry1_page.fetch_uri, allowed_hosts, crawl_ctx.redirects, logger, true, true
  )
  entry1_curis_set = entry1_links
    .map(&:curi)
    .to_canonical_uri_set(curi_eq_cfg)

  two_entries_links = []
  entry2_curis_set = CanonicalUriSet.new([], curi_eq_cfg)
  entry2_links.each do |entry2_link|
    next if entry2_curis_set.include?(entry2_link.curi)

    entry2_curis_set << entry2_link.curi
    two_entries_links << entry2_link if entry1_curis_set.include?(entry2_link.curi)
  end

  two_entries_other_links = []
  two_entries_links.each do |link|
    queryless_curi = canonical_uri_without_query(link.curi)
    next if guided_seen_queryless_curis_set.include?(queryless_curi)

    if link.curi.trimmed_path&.match?(ARCHIVES_REGEX)
      guided_seen_queryless_curis_set << queryless_curi
      archives_queue << link
    elsif link.curi.trimmed_path&.match?(MAIN_PAGE_REGEX)
      guided_seen_queryless_curis_set << queryless_curi
      main_page_queue << link
    else
      two_entries_other_links << link
    end
  end

  logger.log("Two entries links: #{archives_queue.length} archives, #{main_page_queue.length} main page")

  result = guided_crawl_loop(
    [archives_queue, main_page_queue], [archives_pptr_retry_queue, main_page_pptr_retry_queue],
    guided_seen_queryless_curis_set, archives_categories_state, feed_entry_links, feed_entry_curis_set,
    feed_generator, curi_eq_cfg, allowed_hosts, crawl_ctx, mock_http_client, puppeteer_client, start_link_id,
    db_storage, logger
  )
  return result if result

  others_queue = []
  others_pptr_retry_queue = []

  if feed_generator == :medium
    logger.log("Skipping other links because Medium")
  else
    filtered_two_entries_other_links = two_entries_other_links
      .filter { |link| !feed_entry_curis_set.include?(link.curi) }
    if filtered_two_entries_other_links.length > 10
      twice_filtered_two_entries_other_links = filtered_two_entries_other_links.filter do |link|
        !link.curi.trimmed_path&.match?(/\/\d\d\d\d(\/\d\d)?(\/\d\d)?$/)
      end
      logger.log("Two entries other links: filtering #{filtered_two_entries_other_links.length} -> #{twice_filtered_two_entries_other_links.length}")
    else
      twice_filtered_two_entries_other_links = filtered_two_entries_other_links
      logger.log("Two entries other links: #{twice_filtered_two_entries_other_links.length}")
    end

    twice_filtered_two_entries_other_links.each do |link|
      queryless_curi = canonical_uri_without_query(link.curi)
      next if guided_seen_queryless_curis_set.include?(queryless_curi)

      others_queue << link
    end

    filtered_start_page_other_links = start_page_other_links.filter do |link|
      level = link.curi.trimmed_path&.count("/")
      [nil, 1].include?(level) && !link.curi.trimmed_path&.match?(/\/\d\d\d\d(\/\d\d)?(\/\d\d)?$/)
    end
    are_any_feed_entries_top_level = feed_entry_links
      .to_a
      .any? { |entry_link| [nil, 1].include?(entry_link.curi.trimmed_path&.count("/")) }
    if are_any_feed_entries_top_level
      logger.log("Skipping start page other links because some feed entries are top level")
    else
      logger.log("Start page other links: #{filtered_start_page_other_links.length}")
      filtered_start_page_other_links.each do |link|
        queryless_curi = canonical_uri_without_query(link.curi)
        next if guided_seen_queryless_curis_set.include?(queryless_curi)

        others_queue << link
      end
    end

    result = guided_crawl_loop(
      [archives_queue, main_page_queue, others_queue],
      [archives_pptr_retry_queue, main_page_pptr_retry_queue, others_pptr_retry_queue],
      guided_seen_queryless_curis_set, archives_categories_state, feed_entry_links, feed_entry_curis_set,
      feed_generator, curi_eq_cfg, allowed_hosts, crawl_ctx, mock_http_client, puppeteer_client, start_link_id,
      db_storage, logger
    )
    return result if result
  end

  logger.log("Retrying with puppeteer: #{archives_pptr_retry_queue.length} archives, #{main_page_pptr_retry_queue.length} main page, #{others_pptr_retry_queue.length} others")

  result = puppeteer_retry_loop(
    [archives_pptr_retry_queue, main_page_pptr_retry_queue, others_pptr_retry_queue],
    archives_categories_state, feed_entry_links, feed_entry_curis_set, feed_generator, curi_eq_cfg, crawl_ctx,
    mock_http_client, puppeteer_client, start_link_id, db_storage, logger
  )
  return result if result

  logger.log("Pattern not detected")
  nil
end

def guided_crawl_loop(
  queues, pptr_retry_queues, guided_seen_queryless_curis_set, archives_categories_state, feed_entry_links,
  feed_entry_curis_set, feed_generator, curi_eq_cfg, allowed_hosts, crawl_ctx, mock_http_client,
  puppeteer_client, start_link_id, db_storage, logger
)
  logger.log("Guided crawl loop started")

  sorted_results = []
  archives_queue, main_page_queue = queues
  had_archives = !archives_queue.empty?
  loop do
    active_queue_index = queues.index { |queue| !queue.empty? }
    break unless active_queue_index

    active_queue = queues[active_queue_index]
    active_pptr_retry_queue = pptr_retry_queues[active_queue_index]
    link_or_page = active_queue.shift
    if link_or_page.is_a?(Link)
      link = link_or_page
      next if crawl_ctx.fetched_curis.include?(link.curi)

      page = crawl_request(
        link, false, feed_entry_curis_set, crawl_ctx, mock_http_client, puppeteer_client, start_link_id,
        db_storage, logger
      )
      unless page.is_a?(Page) && page.document
        logger.log("Couldn't fetch link: #{page}")
        next
      end
    elsif link_or_page.is_a?(Page)
      page = link_or_page
      link = to_canonical_link(page.fetch_uri.to_s, logger)
    else
      raise "Neither link nor page in the queue: #{link_or_page}"
    end

    active_pptr_retry_queue << [link, page] unless page.is_puppeteer_used
    page_all_links = extract_links(
      page.document, page.fetch_uri, nil, crawl_ctx.redirects, logger, true, true
    )

    page_allowed_hosts_links = page_all_links
      .filter { |page_link| allowed_hosts.include?(page_link.uri.host) }
    page_allowed_hosts_links.each do |page_link|
      queryless_curi = canonical_uri_without_query(page_link.curi)
      next if guided_seen_queryless_curis_set.include?(queryless_curi)

      if page_link.curi.trimmed_path&.match?(ARCHIVES_REGEX)
        guided_seen_queryless_curis_set << queryless_curi
        archives_queue << page_link
        had_archives = true
        logger.log("Enqueueing archives link: #{page_link.curi}")
      elsif page_link.curi.trimmed_path&.match?(MAIN_PAGE_REGEX)
        guided_seen_queryless_curis_set << queryless_curi
        main_page_queue << page_link
        logger.log("Enqueueing main page link: #{page_link.curi}")
      end
    end

    page_curis_set = page_all_links
      .map(&:curi)
      .to_canonical_uri_set(curi_eq_cfg)
    page_results = try_extract_historical(
      link, page, page_all_links, page_curis_set, feed_entry_links, feed_entry_curis_set, feed_generator,
      curi_eq_cfg, archives_categories_state, logger
    )
    page_results.each do |page_result|
      insert_sorted_result(page_result, sorted_results)
    end

    if had_archives && archives_queue.empty? && !sorted_results.empty?
      postprocessed_result = postprocess_results(
        sorted_results, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, start_link_id, db_storage,
        logger
      )
      if postprocessed_result
        if postprocessed_result.count >= 21
          logger.log("Guided crawl loop finished with best result of #{postprocessed_result.count} links")
          return postprocessed_result
        else
          logger.log("Went through all the archives but the best result only has #{postprocessed_result.count} links. Checking others just in case")
          sorted_results.prepend(postprocessed_result)
        end
      end
    end
  end

  postprocessed_result = postprocess_results(
    sorted_results, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, start_link_id, db_storage,
    logger
  )
  if postprocessed_result
    logger.log("Guided crawl loop finished with best result of #{postprocessed_result.count} links")
    return postprocessed_result
  end

  logger.log("Guided crawl loop finished, no result")
  nil
end

def insert_sorted_result(new_result, sorted_results)
  insert_index = sorted_results
    .find_index { |result| result.speculative_count < new_result.speculative_count }
  if insert_index
    sorted_results.insert(insert_index, new_result)
  else
    sorted_results << new_result
  end
end

def postprocess_results(
  sorted_results, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, start_link_id, db_storage,
  logger
)
  sorted_results_log = sorted_results.map { |result| [result.class.name, result.main_link.url, result.speculative_count] }
  logger.log("Postprocessing #{sorted_results.length} results: #{sorted_results_log}")

  until sorted_results.empty?
    result = sorted_results.shift
    if result.count
      pp_result = result
    else
      if result.is_a?(ArchivesMediumPinnedEntryResult)
        pp_result = postprocess_archives_medium_pinned_entry_result(
          result, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, start_link_id, db_storage,
          logger
        )
      elsif result.is_a?(ArchivesShuffledResults)
        pp_result = postprocess_archives_shuffled_results(
          result, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, start_link_id, db_storage,
          logger
        )
      elsif result.is_a?(ArchivesCategoriesResult)
        pp_result = postprocess_archives_categories_result(
          result, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, start_link_id, db_storage,
          logger
        )
      elsif result.is_a?(Page1Result)
        # If page 1 result looks the best, check just page 2 in case it was a scam
        pp_result = postprocess_page1_result(
          result, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, start_link_id, db_storage,
          logger
        )
      elsif result.is_a?(PartialPagedResult)
        pp_result = postprocess_paged_result(
          result, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, start_link_id, db_storage,
          logger
        )
      else
        raise "Unknown result type: #{result}"
      end
    end
    next unless pp_result

    if sorted_results.empty? ||
      pp_result.speculative_count > sorted_results.first.speculative_count ||
      (!pp_result.is_a?(PartialPagedResult) &&
        pp_result.speculative_count == sorted_results.first.speculative_count)

      if pp_result.is_a?(PartialPagedResult)
        pp_result = postprocess_paged_result(
          pp_result, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, start_link_id, db_storage,
          logger
        )
      end

      return pp_result
    end

    insert_sorted_result(pp_result, sorted_results)
  end

  nil
end

def puppeteer_retry_loop(
  queues, archives_categories_state, feed_entry_links, feed_entry_curis_set, feed_generator, curi_eq_cfg,
  crawl_ctx, mock_http_client, puppeteer_client, start_link_id, db_storage, logger
)
  logger.log("Puppeteer retry loop start")

  sorted_results = []
  archives_queue = queues.first
  had_archives = !archives_queue.empty?
  loop do
    active_queue = queues.find { |queue| !queue.empty? }
    break unless active_queue

    link, page = active_queue.shift
    content, document = puppeteer_client.fetch(link, feed_entry_curis_set, crawl_ctx, logger)
    pptr_page = Page.new(
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

    pptr_page_links = extract_links(
      pptr_page.document, pptr_page.fetch_uri, nil, crawl_ctx.redirects, logger, true, true
    )
    pptr_page_curis_set = pptr_page_links
      .map(&:curi)
      .to_canonical_uri_set(curi_eq_cfg)
    page_results = try_extract_historical(
      link, pptr_page, pptr_page_links, pptr_page_curis_set, feed_entry_links,
      feed_entry_curis_set, feed_generator, curi_eq_cfg, archives_categories_state, logger
    )
    page_results.each do |page_result|
      insert_sorted_result(page_result, sorted_results)
    end

    if had_archives && archives_queue.empty? && !sorted_results.empty?
      postprocessed_result = postprocess_results(
        sorted_results, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, start_link_id, db_storage,
        logger
      )
      if postprocessed_result
        if postprocessed_result.count >= 21
          logger.log("Puppeteer retry loop finished with best result of #{postprocessed_result.count} links")
          return postprocessed_result
        else
          logger.log("Went through all the archives but the best result only has #{postprocessed_result.count} links. Checking others just in case")
          sorted_results.prepend(postprocessed_result)
        end
      end
    end
  end

  postprocessed_result = postprocess_results(
    sorted_results, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, start_link_id, db_storage,
    logger
  )
  if postprocessed_result
    logger.log("Puppeteer retry loop finished with best result of #{postprocessed_result.count} links")
    return postprocessed_result
  end

  logger.log("Puppeteer retry loop finished, no result")
  nil
end

def try_extract_historical(
  page_link, page, page_links, page_curis_set, feed_entry_links, feed_entry_curis_set, feed_generator,
  curi_eq_cfg, archives_categories_state, logger
)
  logger.log("Trying to extract historical from #{page.fetch_uri}")
  results = []

  archives_almost_match_threshold = get_archives_almost_match_threshold(feed_entry_links.length)
  extractions_by_masked_xpath_by_star_count = get_extractions_by_masked_xpath_by_star_count(
    page_links, feed_entry_links, feed_entry_curis_set, curi_eq_cfg, archives_almost_match_threshold, logger
  )

  archives_results = try_extract_archives(
    page_link, page, page_links, page_curis_set, feed_entry_links, feed_entry_curis_set, feed_generator,
    extractions_by_masked_xpath_by_star_count, archives_almost_match_threshold, curi_eq_cfg, logger
  )
  results.push(*archives_results)

  archives_categories_result = try_extract_archives_categories(
    page_link, page, page_curis_set, feed_entry_links, feed_entry_curis_set,
    extractions_by_masked_xpath_by_star_count, archives_categories_state, curi_eq_cfg, logger
  )
  results << archives_categories_result if archives_categories_result

  page1_result = try_extract_page1(
    page_link, page, page_links, page_curis_set, feed_entry_links, feed_entry_curis_set, feed_generator,
    curi_eq_cfg, logger
  )
  results << page1_result if page1_result

  results
end

PostprocessedResult = Struct.new(
  :main_link, :pattern, :links, :speculative_count, :count, :extra, keyword_init: true
)

def postprocess_archives_medium_pinned_entry_result(
  medium_result, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, start_link_id, db_storage, logger
)
  pinned_entry_page = crawl_request(
    medium_result.pinned_entry_link, false, nil, crawl_ctx, mock_http_client, nil, start_link_id, db_storage,
    logger
  )
  unless pinned_entry_page.is_a?(Page) && pinned_entry_page.document
    logger.log("Couldn't fetch first Medium link during result postprocess: #{pinned_entry_page}")
    return nil
  end

  pinned_entry_page_links = extract_links(
    pinned_entry_page.document, pinned_entry_page.fetch_uri, [pinned_entry_page.fetch_uri.host],
    crawl_ctx.redirects, logger
  )

  sorted_links = historical_archives_medium_sort_finish(
    medium_result.pinned_entry_link, pinned_entry_page_links, medium_result.other_links_dates, curi_eq_cfg
  )
  unless sorted_links
    logger.log("Couldn't sort links during result postprocess")
    return nil
  end

  return nil unless compare_with_feed(sorted_links, feed_entry_links, curi_eq_cfg, logger)

  PostprocessedResult.new(
    main_link: medium_result.main_link,
    pattern: medium_result.pattern,
    links: sorted_links,
    speculative_count: sorted_links.length,
    count: sorted_links.length,
    extra: medium_result.extra
  )
end

def postprocess_archives_shuffled_results(
  shuffled_results, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, start_link_id, db_storage,
  logger
)
  pages_by_canonical_url = {}
  sorted_tentative_results = shuffled_results.results.sort_by { |tentative_result| tentative_result.count }

  best_result = nil
  sorted_tentative_results.each do |tentative_result|
    sorted_links = postprocess_sort_links_maybe_dates(
      tentative_result.links_maybe_dates, feed_entry_links, curi_eq_cfg, pages_by_canonical_url, crawl_ctx,
      mock_http_client, start_link_id, db_storage, logger
    )
    return best_result unless sorted_links

    best_result = PostprocessedResult.new(
      main_link: shuffled_results.main_link,
      pattern: tentative_result.pattern,
      links: sorted_links,
      speculative_count: sorted_links.length,
      count: sorted_links.length,
      extra: tentative_result.extra
    )
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
    main_link: archives_categories_result.main_link,
    pattern: archives_categories_result.pattern,
    links: sorted_links,
    speculative_count: sorted_links.length,
    count: sorted_links.length,
    extra: archives_categories_result.extra
  )
end

def postprocess_page1_result(
  page1_result, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client,
  start_link_id, db_storage, logger
)
  page2 = crawl_request(
    page1_result.link_to_page2, false, nil, crawl_ctx, mock_http_client, nil, start_link_id, db_storage,
    logger
  )
  unless page2 && page2.is_a?(Page) && page2.document
    logger.log("Page 2 is not a page: #{page2}")
    return nil
  end

  paged_result = try_extract_page2(page2, page1_result.paged_state, feed_entry_links, curi_eq_cfg, logger)
  paged_result
end

def postprocess_paged_result(
  paged_result, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, start_link_id, db_storage, logger
)
  while paged_result.is_a?(PartialPagedResult)
    page = crawl_request(
      paged_result.link_to_next_page, false, nil, crawl_ctx, mock_http_client, nil, start_link_id, db_storage,
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
        link, false, nil, crawl_ctx, mock_http_client, nil, start_link_id, db_storage, logger
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

def canonical_uri_without_query(curi)
  CanonicalUri.new(curi.host, curi.port, curi.path, nil)
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