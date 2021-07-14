require 'set'
require_relative 'crawling'
require_relative 'historical_archives'
require_relative 'historical_paged'
require_relative 'structs'

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
  [:is_start_page_main_page, :boolean],
  [:does_start_page_link_to_main_page, :boolean],
  [:is_main_page_linked_from_both_entries, :boolean],
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

  def run(start_link_id, save_successes, db, logger)
    guided_crawl(start_link_id, save_successes, db, logger)
  end

  attr_reader :result_column_names
end

def guided_crawl(start_link_id, save_successes, db, logger)
  start_link_row = db.exec_params('select url, rss_url from start_links where id = $1', [start_link_id])[0]
  start_link_url = start_link_row["url"]
  start_link_feed_url = start_link_row["rss_url"]
  result = RunResult.new(GUIDED_CRAWLING_RESULT_COLUMNS)
  result.start_url = "<a href=\"#{start_link_url}\">#{start_link_url}</a>"
  ctx = CrawlContext.new
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
    end

    gt_row = db.exec_params(
      "select pattern, entries_count, main_page_canonical_url, oldest_entry_canonical_url from historical_ground_truth where start_link_id = $1",
      [start_link_id]
    ).first
    if gt_row
      result.gt_pattern = gt_row["pattern"]
    end

    mock_http_client = MockJitHttpClient.new(db, start_link_id)
    mock_db_storage = GuidedCrawlMockDbStorage.new(db, start_link_id)
    db.exec_params('delete from feeds where start_link_id = $1', [start_link_id])
    db.exec_params('delete from pages where start_link_id = $1', [start_link_id])
    db.exec_params('delete from permanent_errors where start_link_id = $1', [start_link_id])
    db.exec_params('delete from redirects where start_link_id = $1', [start_link_id])
    db.exec_params('delete from historical where start_link_id = $1', [start_link_id])
    db_storage = CrawlDbStorage.new(db, mock_db_storage)

    start_link = to_canonical_link(start_link_url, logger)
    raise "Bad start link: #{start_link_url}" if start_link.nil?

    ctx.allowed_hosts << start_link.uri.host
    start_result = crawl_request(
      start_link, ctx, mock_http_client, false, start_link_id, db_storage, logger
    )
    raise "Unexpected start result: #{start_result}" unless start_result.is_a?(Page) && start_result.content
    start_page = start_result

    feed_start_time = monotonic_now
    if start_link_feed_url
      feed_link = to_canonical_link(start_link_feed_url, logger)
      raise "Bad feed link: #{start_link_feed_url}" if feed_link.nil?
    else
      ctx.seen_fetch_urls << start_result.fetch_uri.to_s
      start_document = nokogiri_html5(start_page.content)
      feed_links = start_document
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
    ctx.allowed_hosts << feed_link.uri.host
    feed_result = crawl_request(
      feed_link, ctx, mock_http_client, true, start_link_id, db_storage, logger
    )
    raise "Unexpected feed result: #{feed_result}" unless feed_result.is_a?(Page) && feed_result.content

    feed_page = feed_result
    ctx.seen_fetch_urls << feed_page.fetch_uri.to_s
    db_storage.save_feed(start_link_id, feed_page.canonical_uri.to_s)
    result.feed_requests_made = ctx.requests_made
    result.feed_time = (monotonic_now - feed_start_time).to_i
    logger.log("Feed url: #{feed_page.canonical_uri}")

    feed_links = extract_feed_links(feed_page.content, feed_page.fetch_uri, logger)
    result.feed_links = feed_links.entry_links.length
    logger.log("Root url: #{feed_links.root_link}")
    logger.log("Entries in feed: #{feed_links.entry_links.length}")

    feed_entry_hosts = Set.new
    if feed_links.root_link
      ctx.allowed_hosts << feed_links.root_link.uri.host
    end
    feed_links.entry_links.each do |entry_link|
      ctx.allowed_hosts << entry_link.uri.host
      feed_entry_hosts << entry_link.uri.host
    end

    same_hosts = Set.new
    [[start_link, start_page], [feed_link, feed_page]].each do |link, page|
      if link.uri.host != page.fetch_uri.host &&
        canonical_uri_same_path?(link.canonical_uri, page.canonical_uri) &&
        (feed_entry_hosts.include?(link.uri.host) || feed_entry_hosts.include?(page.fetch_uri.host))

        same_hosts << link.uri.host << page.fetch_uri.host
      end
    end

    canonical_equality_cfg = CanonicalEqualityConfig.new(same_hosts, feed_links.is_tumblr)
    ctx.fetched_canonical_uris.update_equality_config(canonical_equality_cfg)
    historical_result_combo = guided_crawl_loop(
      start_link_id, start_page, feed_links.entry_links, ctx, canonical_equality_cfg, mock_http_client,
      db_storage, CanonicalUri.from_db_string(gt_row["main_page_canonical_url"]), logger
    )
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

    entries_count = historical_result[:links].length
    oldest_link = historical_result[:links][-1]
    logger.log("Historical links: #{entries_count}")
    historical_result[:links].each do |historical_link|
      logger.log(historical_link.url)
    end

    db.exec_params(
      "insert into historical (start_link_id, pattern, entries_count, main_page_canonical_url, oldest_entry_canonical_url) values ($1, $2, $3, $4, $5)",
      [start_link_id, historical_result[:pattern], entries_count, historical_result[:main_canonical_url], oldest_link.canonical_uri.to_s]
    )

    if gt_row
      historical_links_matching = true

      if historical_result[:pattern] == gt_row["pattern"]
        result.historical_links_pattern_status = :success
        result.historical_links_pattern = historical_result[:pattern]
      else
        result.historical_links_pattern_status = :failure
        result.historical_links_pattern = "#{historical_result[:pattern]}<br>(#{gt_row["pattern"]})"
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
      if gt_main_url == historical_result[:main_canonical_url]
        result.main_url = "<a href=\"#{historical_result[:main_fetch_url]}\">#{historical_result[:main_canonical_url]}</a>"
      else
        result.main_url = "<a href=\"#{historical_result[:main_fetch_url]}\">#{historical_result[:main_canonical_url]}</a><br>(#{gt_row["main_page_canonical_url"]})"
      end

      gt_oldest_canonical_uri = CanonicalUri.from_db_string(gt_row["oldest_entry_canonical_url"])
      if !canonical_uri_equal?(gt_oldest_canonical_uri, oldest_link.canonical_uri, canonical_equality_cfg)
        historical_links_matching = false
        result.oldest_link_status = :failure
        result.oldest_link = "<a href=\"#{oldest_link.url}\">#{oldest_link.canonical_uri}</a><br>(#{gt_oldest_canonical_uri})"
      else
        result.oldest_link_status = :success
        result.oldest_link = "<a href=\"#{oldest_link.url}\">#{oldest_link.canonical_uri}</a>"
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
      result.historical_links_pattern = historical_result[:pattern]
      result.historical_links_count = entries_count
      result.main_url = "<a href=\"#{historical_result[:main_fetch_url]}\">#{historical_result[:main_canonical_url]}</a>"
      result.oldest_link = "<a href=\"#{oldest_link.url}\">#{oldest_link.canonical_uri}</a>"
    end

    result.extra = historical_result[:extra]

    result
  rescue => e
    raise RunError.new(e.message, result), e
  ensure
    result.duplicate_fetches = ctx.duplicate_fetches
    result.total_requests = ctx.requests_made
    result.total_pages = ctx.fetched_canonical_uris.length
    result.total_network_requests = defined?(mock_http_client) && mock_http_client && mock_http_client.network_requests_made
    result.total_time = (monotonic_now - start_time).to_i
  end
end

ARCHIVES_REGEX = "/(?:archives?|posts?|all)(?:\\.[a-z]+)?/*$"
MAIN_PAGE_REGEX = "/(?:archives?|blog|posts?|articles|writing|journal|all)(?:\\.[a-z]+)?/*$"

def guided_crawl_loop(
  start_link_id, start_page, feed_entry_links, ctx, canonical_equality_cfg, mock_http_client,
  db_storage, gt_main_page_canonical_uri, logger
)
  start_page_links = extract_links(start_page, nil, ctx.redirects, logger, true, true)
  start_page_canonical_uris_set = start_page_links
    .map(&:canonical_uri)
    .to_canonical_uri_set(canonical_equality_cfg)
  feed_entry_canonical_uris = feed_entry_links.map(&:canonical_uri)
  feed_entry_canonical_uris_set = feed_entry_canonical_uris.to_canonical_uri_set(canonical_equality_cfg)

  does_start_page_path_match_archives = start_page.canonical_uri.path.match?(ARCHIVES_REGEX)
  if does_start_page_path_match_archives
    start_page_result = try_extract_historical(
      start_page, start_page_links, start_page_canonical_uris_set, feed_entry_canonical_uris,
      feed_entry_canonical_uris_set, canonical_equality_cfg, start_link_id, ctx, mock_http_client,
      db_storage, logger
    )

    return { best_result: start_page_result } if start_page_result
    logger.log("Start page matches archives regex but is not the main page")
  else
    logger.log("Start page doesn't match archives regex")
  end

  logger.log("Trying select links from start page")

  allowed_hosts = canonical_equality_cfg.same_hosts.empty? ?
    [start_page.canonical_uri.host] :
    canonical_equality_cfg.same_hosts

  start_page_archives_links = start_page_links
    .filter { |link| allowed_hosts.include?(link.uri.host) && link.canonical_uri.path.match?(ARCHIVES_REGEX) }
  logger.log("Checking #{start_page_archives_links.length} archives links")
  start_page_archives_links_result = crawl_historical(
    start_page_archives_links, feed_entry_canonical_uris, feed_entry_canonical_uris_set,
    canonical_equality_cfg, start_link_id, ctx, mock_http_client, db_storage, logger
  )
  return { best_result: start_page_archives_links_result } if start_page_archives_links_result

  start_page_main_page_links = start_page_links
    .filter { |link| allowed_hosts.include?(link.uri.host) && link.canonical_uri.path.match?(MAIN_PAGE_REGEX) }
  logger.log("Checking #{start_page_main_page_links.length} main page links")
  start_page_main_page_links_result = crawl_historical(
    start_page_main_page_links, feed_entry_canonical_uris, feed_entry_canonical_uris_set,
    canonical_equality_cfg, start_link_id, ctx, mock_http_client, db_storage, logger
  )
  return { best_result: start_page_main_page_links_result } if start_page_main_page_links_result
  logger.log("Start page doesn't link to the main page")

  unless does_start_page_path_match_archives
    start_page_result = try_extract_historical(
      start_page, start_page_links, start_page_canonical_uris_set, feed_entry_canonical_uris,
      feed_entry_canonical_uris_set, canonical_equality_cfg, start_link_id, ctx, mock_http_client,
      db_storage, logger
    )

    return { best_result: start_page_result } if start_page_result
    logger.log("Start page doesn't match archives regex and is not the main page")
  end

  logger.log("Trying common links from the first two entries")

  raise "Too few entries in feed: #{feed_entry_links.length}" if feed_entry_links.length < 2
  entry1_page = crawl_request(feed_entry_links[0], ctx, mock_http_client, false, start_link_id, db_storage, logger)
  entry2_page = crawl_request(feed_entry_links[1], ctx, mock_http_client, false, start_link_id, db_storage, logger)
  raise "Couldn't fetch entry 1: #{entry1_page}" if !entry1_page.is_a?(Page) || !entry1_page.content
  raise "Couldn't fetch entry 2: #{entry2_page}" if !entry2_page.is_a?(Page) || !entry2_page.content

  entry1_links = extract_links(entry1_page, allowed_hosts, ctx.redirects, logger, true, true)
  entry2_links = extract_links(entry2_page, allowed_hosts, ctx.redirects, logger, true, true)
  entry1_canonical_uris_set = entry1_links
    .map(&:canonical_uri)
    .to_canonical_uri_set(canonical_equality_cfg)
  entry2_canonical_uris_set = entry2_links
    .map(&:canonical_uri)
    .to_canonical_uri_set(canonical_equality_cfg)

  links_from_both_entries = []
  entry1_canonical_uris_set2 = CanonicalUriSet.new([], canonical_equality_cfg)
  entry1_links.each do |entry1_link|
    next if entry1_canonical_uris_set2.include?(entry1_link.canonical_uri)

    entry1_canonical_uris_set2 << entry1_link.canonical_uri
    links_from_both_entries << entry1_link if entry2_canonical_uris_set.include?(entry1_link.canonical_uri)
  end

  archives_links_from_both_entries, non_archives_links_from_both_entries = links_from_both_entries
    .partition { |link| link.canonical_uri.path.match?(ARCHIVES_REGEX) }
  logger.log("Checking #{archives_links_from_both_entries.length} archives links")
  archives_links_from_both_entries_result = crawl_historical(
    archives_links_from_both_entries, feed_entry_canonical_uris, feed_entry_canonical_uris_set,
    canonical_equality_cfg, start_link_id, ctx, mock_http_client, db_storage, logger
  )
  return { best_result: archives_links_from_both_entries_result } if archives_links_from_both_entries_result

  main_page_links_from_both_entries, other_links_from_both_entries = non_archives_links_from_both_entries
    .partition { |link| link.canonical_uri.path.match?(MAIN_PAGE_REGEX) }
  logger.log("Checking #{main_page_links_from_both_entries.length} main page links")
  main_page_links_from_both_entries_result = crawl_historical(
    main_page_links_from_both_entries, feed_entry_canonical_uris, feed_entry_canonical_uris_set,
    canonical_equality_cfg, start_link_id, ctx, mock_http_client, db_storage, logger
  )
  return { best_result: main_page_links_from_both_entries_result } if main_page_links_from_both_entries_result

  logger.log("Checking #{other_links_from_both_entries.length} other links")
  other_links_from_both_entries_result = crawl_historical(
    other_links_from_both_entries, feed_entry_canonical_uris, feed_entry_canonical_uris_set,
    canonical_equality_cfg, start_link_id, ctx, mock_http_client, db_storage, logger
  )
  return { best_result: other_links_from_both_entries_result } if other_links_from_both_entries_result
  logger.log("Pattern not detected")

  # STATS
  is_start_page_main_page = canonical_uri_equal?(
    start_page.canonical_uri, gt_main_page_canonical_uri, canonical_equality_cfg
  )
  does_start_page_link_to_main_page = start_page_canonical_uris_set.include?(gt_main_page_canonical_uri)
  is_main_page_linked_from_both_entries =
    entry1_canonical_uris_set.include?(gt_main_page_canonical_uri) &&
      entry2_canonical_uris_set.include?(gt_main_page_canonical_uri)

  unless is_start_page_main_page || does_start_page_link_to_main_page
    logger.log("Would need to crawl #{links_from_both_entries.length} links common for two entries:")
    links_from_both_entries.each do |uri|
      logger.log(uri)
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
  links, feed_entry_canonical_uris, feed_entry_canonical_uris_set, canonical_equality_cfg, start_link_id, ctx,
  mock_http_client, db_storage, logger
)
  links.each do |link|
    next if ctx.fetched_canonical_uris.include?(link.canonical_uri)

    link_page = crawl_request(link, ctx, mock_http_client, false, start_link_id, db_storage, logger)
    unless link_page.is_a?(Page) && link_page.content
      logger.log("Couldn't fetch link: #{link_page}")
      next
    end

    link_page_links = extract_links(link_page, nil, ctx.redirects, logger, true, true)
    link_page_canonical_uris_set = link_page_links
      .map(&:canonical_uri)
      .to_canonical_uri_set(canonical_equality_cfg)
    link_result = try_extract_historical(
      link_page, link_page_links, link_page_canonical_uris_set, feed_entry_canonical_uris,
      feed_entry_canonical_uris_set, canonical_equality_cfg, start_link_id, ctx, mock_http_client,
      db_storage, logger
    )

    return link_result if link_result
  end
  nil
end

def try_extract_historical(
  page, page_links, page_canonical_uris_set, feed_entry_canonical_uris, feed_entry_canonical_uris_set,
  canonical_equality_cfg, start_link_id, ctx, mock_http_client, db_storage, logger
)
  paged_result = try_extract_paged(
    page, page_links, page_canonical_uris_set, feed_entry_canonical_uris, feed_entry_canonical_uris_set,
    canonical_equality_cfg, 1, start_link_id, ctx, mock_http_client, db_storage, logger
  )

  archives_result = try_extract_archives(
    page, page_links, page_canonical_uris_set, feed_entry_canonical_uris, feed_entry_canonical_uris_set,
    canonical_equality_cfg, nil, 1, logger
  )

  if paged_result && archives_result
    if paged_result[:count] > archives_result[:count]
      paged_result[:best_result]
    else
      archives_result[:best_result]
    end
  elsif paged_result
    paged_result[:best_result]
  elsif archives_result
    archives_result[:best_result]
  end
end
