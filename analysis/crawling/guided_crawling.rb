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
  [:historical_links_found, :boolean],
  [:historical_links_matching, :boolean],
  [:no_regression, :neutral],
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

  def run(start_link_id, _, db, logger)
    guided_crawl(start_link_id, db, logger)
  end

  attr_reader :result_column_names
end

def guided_crawl(start_link_id, db, logger)
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
    result.feed_url = "<a href=\"#{feed_link.url}\">#{feed_link.canonical_uri.to_s}</a>"
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

    host_redirect = compute_host_redirect(start_link, start_page, feed_link, feed_page)
    feed_links = extract_feed_links(feed_page.content, feed_page.fetch_uri, host_redirect, logger)
    result.feed_links = feed_links.entry_links.length
    logger.log("Root url: #{feed_links.root_link}")
    logger.log("Entries in feed: #{feed_links.entry_links.length}")

    if feed_links.root_link
      ctx.allowed_hosts << feed_links.root_link.uri.host
    end
    feed_links.entry_links.each do |entry_link|
      ctx.allowed_hosts << entry_link.uri.host
    end
    feed_entry_canonical_uris = feed_links.entry_links.map(&:canonical_uri)

    canonical_equality_cfg = CanonicalEqualityConfig.new(Set.new, feed_links.is_tumblr)
    historical_result = guided_crawl_loop(
      start_link_id, start_page, feed_entry_canonical_uris, ctx, canonical_equality_cfg, mock_http_client,
      db_storage, logger
    )
    result.historical_links_found = !!historical_result
    has_succeeded_before = db
      .exec_params("select count(*) from successes where start_link_id = $1", [start_link_id])
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
    else
      result.historical_links_matching = '?'
      result.historical_links_matching_status = :neutral
      result.no_regression_status = :neutral
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
    result.total_pages = ctx.fetched_urls.length
    result.total_network_requests = defined?(mock_http_client) && mock_http_client && mock_http_client.network_requests_made
    result.total_time = (monotonic_now - start_time).to_i
  end
end

def compute_host_redirect(start_link, start_page, feed_link, feed_page)
  start_same_path = canonical_uri_same_path?(start_link.canonical_uri, start_page.canonical_uri)
  feed_same_path = canonical_uri_same_path?(feed_link.canonical_uri, feed_page.canonical_uri)
  start_from_host = start_link.uri.host
  start_to_host = start_page.fetch_uri.host
  feed_from_host = feed_link.uri.host
  feed_to_host = feed_page.fetch_uri.host

  if !start_same_path
    # Can't say anything about redirects
    return HostRedirectConfig.new(nil, nil, nil)
  elsif !feed_same_path
    # Feed redirect should be ignored but start redirect is informative
    return HostRedirectConfig.new(start_from_host, start_to_host, nil)
  end

  # Both start and feed paths are the same, now we can look at hosts

  all_hosts = [start_from_host, start_to_host, feed_from_host, feed_to_host]
  raise "Too many hosts: #{all_hosts}" if all_hosts.to_set.length > 2

  base_host = start_from_host
  if start_to_host == base_host && feed_from_host == base_host && feed_to_host == base_host
    # A: No redirects observed
    HostRedirectConfig.new(nil, nil, nil)
  elsif start_to_host == base_host && feed_from_host == base_host && feed_to_host != base_host
    # B: RSS must be hosted elsewhere and entries shouldn't be hosted there
    HostRedirectConfig.new(nil, nil, feed_to_host)
  elsif start_to_host == base_host && feed_from_host != base_host && feed_to_host == base_host
    # C: RSS uncovered redirect from old to new host
    HostRedirectConfig.new(feed_from_host, base_host, nil)
  elsif start_to_host == base_host && feed_from_host != base_host && feed_to_host != base_host
    # B: RSS must be hosted elsewhere and entries shouldn't be hosted there
    HostRedirectConfig.new(nil, nil, feed_to_host)
  elsif start_to_host != base_host && feed_from_host == base_host && feed_to_host == base_host
    # D
    raise "Start page redirects from A to B but RSS stays at A: #{all_hosts}"
  elsif start_to_host != base_host && feed_from_host == base_host && feed_to_host != base_host
    # E: Both start page and RSS redirect from base host to another one
    HostRedirectConfig.new(base_host, start_to_host, nil)
  elsif start_to_host != base_host && feed_from_host != base_host && feed_to_host == base_host
    # F
    raise "Start page redirects from A to B, RSS redirects from B to A: #{all_hosts}"
  elsif start_to_host != base_host && feed_from_host != base_host && feed_to_host != base_host
    # E: Start page redirects from base host to the one that also has RSS
    HostRedirectConfig.new(base_host, start_to_host, nil)
  else
    raise "Host redirect check is not exhaustive"
  end
end

def guided_crawl_loop(
  start_link_id, start_page, feed_entry_canonical_uris, ctx, canonical_equality_cfg, mock_http_client,
  db_storage, logger
)
  start_page_links = extract_links(start_page, nil, ctx.redirects, logger, true, true)
  start_page_canonical_uris_set = start_page_links
    .map(&:canonical_uri)
    .to_canonical_uri_set(canonical_equality_cfg)
  feed_entry_canonical_uris_set = feed_entry_canonical_uris.to_canonical_uri_set(canonical_equality_cfg)

  paged_result = try_extract_paged(
    start_page, start_page_links, start_page_canonical_uris_set, feed_entry_canonical_uris,
    feed_entry_canonical_uris_set, canonical_equality_cfg, 0, start_link_id, ctx, mock_http_client,
    db_storage, logger
  )

  archives_result = try_extract_archives(
    start_page, start_page_links, start_page_canonical_uris_set, feed_entry_canonical_uris,
    feed_entry_canonical_uris_set, canonical_equality_cfg, nil, 1, logger
  )

  if paged_result && archives_result
    if paged_result[:count] > archives_result[:count]
      return paged_result[:best_result]
    else
      return archives_result[:best_result]
    end
  elsif paged_result
    return paged_result[:best_result]
  elsif archives_result
    return archives_result[:best_result]
  end

  logger.log("Pattern not detected")
end