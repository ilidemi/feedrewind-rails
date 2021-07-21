require 'nokogumbo'
require_relative 'canonical_link'
require_relative 'crawling_storage'
require_relative 'feed_parsing'
require_relative 'historical_archives'
require_relative 'historical_paged'
require_relative 'http_client'
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

  def run(start_link_id, save_successes, allow_puppeteer, db, logger)
    guided_crawl(start_link_id, save_successes, allow_puppeteer, db, logger)
  end

  attr_reader :result_column_names
end

class CrawlContext
  def initialize
    @seen_fetch_urls = Set.new
    @fetched_canonical_uris = CanonicalUriSet.new([], CanonicalEqualityConfig.new(Set.new, false))
    @pptr_fetched_canonical_uris = CanonicalUriSet.new([], CanonicalEqualityConfig.new(Set.new, false))
    @redirects = {}
    @requests_made = 0
    @puppeteer_requests_made = 0
    @duplicate_fetches = 0
    @main_feed_fetched = false
    @allowed_hosts = Set.new
  end

  attr_reader :seen_fetch_urls, :fetched_canonical_uris, :pptr_fetched_canonical_uris, :redirects, :allowed_hosts
  attr_accessor :requests_made, :puppeteer_requests_made, :duplicate_fetches, :main_feed_fetched
end

def guided_crawl(start_link_id, save_successes, allow_puppeteer, db, logger)
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

    ctx.allowed_hosts << start_link.uri.host
    start_result = crawl_request(
      start_link, ctx, mock_http_client, puppeteer_client, false, start_link_id, db_storage,
      logger
    )
    raise "Unexpected start result: #{start_result}" unless start_result.is_a?(Page) && start_result.content
    start_page = start_result

    feed_start_time = monotonic_now
    if start_link_feed_url
      feed_link = to_canonical_link(start_link_feed_url, logger)
      raise "Bad feed link: #{start_link_feed_url}" if feed_link.nil?
    else
      ctx.seen_fetch_urls << start_result.fetch_uri.to_s
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
    ctx.allowed_hosts << feed_link.uri.host
    feed_result = crawl_request(
      feed_link, ctx, mock_http_client, nil, true, start_link_id, db_storage,
      logger
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

    canonical_equality_cfg = CanonicalEqualityConfig.new(same_hosts, feed_links.generator == :tumblr)
    ctx.fetched_canonical_uris.update_equality_config(canonical_equality_cfg)
    ctx.pptr_fetched_canonical_uris.update_equality_config(canonical_equality_cfg)
    gt_main_page_canonical_uri = CanonicalUri.from_db_string(
      gt_row ? gt_row["main_page_canonical_url"] : "no-ground-truth.com"
    )
    historical_result_combo = guided_crawl_loop(
      start_link_id, start_page, feed_links.entry_links, feed_links.generator, ctx, canonical_equality_cfg,
      mock_http_client, puppeteer_client, db_storage, gt_main_page_canonical_uri, logger
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
    result.total_requests = ctx.requests_made + ctx.puppeteer_requests_made
    result.total_pages = ctx.fetched_canonical_uris.length
    result.total_network_requests =
      ((defined?(mock_http_client) && mock_http_client && mock_http_client.network_requests_made) || 0) +
        ctx.puppeteer_requests_made
    result.total_time = (monotonic_now - start_time).to_i
  end
end

PERMANENT_ERROR_CODES = %w[400 401 402 403 404 405 406 407 410 411 412 413 414 415 416 417 418 451]

AlreadySeenLink = Struct.new(:link)
BadRedirection = Struct.new(:url)

def crawl_request(
  initial_link, ctx, http_client, puppeteer_client, is_feed_expected, start_link_id, storage, logger
)
  link = initial_link
  seen_urls = [link.url]
  link = follow_cached_redirects(link, ctx.redirects, seen_urls)
  if !link.equal?(initial_link) &&
    (ctx.seen_fetch_urls.include?(link.url) ||
      ctx.fetched_canonical_uris.include?(link.canonical_uri))

    logger.log("Cached redirect #{initial_link.url} -> #{link.url} (already seen)")
    return AlreadySeenLink.new(link)
  end
  resp = nil
  request_ms = nil

  loop do
    request_start = monotonic_now
    resp = http_client.request(link.uri, logger)
    request_ms = ((monotonic_now - request_start) * 1000).to_i
    ctx.requests_made += 1

    break unless resp.code.start_with?('3')

    redirection_url = resp.location
    redirection_link = to_canonical_link(redirection_url, logger, link.uri)

    if redirection_link.nil?
      logger.log("Bad redirection link")
      return BadRedirection.new(redirection_url)
    end

    if seen_urls.include?(redirection_link.url)
      raise "Circular redirect for #{initial_link.url}: #{seen_urls} -> #{redirection_link.url}"
    end
    seen_urls << redirection_link.url
    ctx.redirects[link.url] = redirection_link
    storage.save_redirect(link.url, redirection_link.url, start_link_id)
    redirection_link = follow_cached_redirects(redirection_link, ctx.redirects, seen_urls)

    if ctx.seen_fetch_urls.include?(redirection_link.url) ||
      ctx.fetched_canonical_uris.include?(redirection_link.canonical_uri)

      logger.log("#{resp.code} #{request_ms}ms #{link.url} -> #{redirection_link.url} (already seen)")
      return AlreadySeenLink.new(link)
    end

    logger.log("#{resp.code} #{request_ms}ms #{link.url} -> #{redirection_link.url}")
    # Not marking canonical url as seen because redirect key is a fetch url which may be different for the
    # same canonical url
    ctx.seen_fetch_urls << redirection_link.url
    ctx.allowed_hosts << redirection_link.uri.host
    link = redirection_link
  end

  if resp.code == "200"
    content_type = resp.content_type ? resp.content_type.split(';')[0] : nil
    if content_type == "text/html"
      content = resp.body
      document = nokogiri_html5(content)
    elsif is_feed_expected && is_feed(resp.body, logger)
      content = resp.body
      document = nil
    else
      content = nil
      document = nil
    end

    if !ctx.fetched_canonical_uris.include?(link.canonical_uri)
      ctx.fetched_canonical_uris << link.canonical_uri
      storage.save_page(
        link.canonical_uri.to_s, link.url, content_type, start_link_id, content, false
      )
      logger.log("#{resp.code} #{content_type} #{request_ms}ms #{link.url}")
    else
      logger.log("#{resp.code} #{content_type} #{request_ms}ms #{link.url} - canonical uri already seen")
    end

    # TODO: puppeteer will be executed twice for duplicate fetches
    content, document, is_puppeteer_used = crawl_link_with_puppeteer(
      link, content, document, puppeteer_client, ctx, logger
    )
    if is_puppeteer_used
      if !ctx.pptr_fetched_canonical_uris.include?(link.canonical_uri)
        ctx.pptr_fetched_canonical_uris << link.canonical_uri
        storage.save_page(
          link.canonical_uri.to_s, link.url, content_type, start_link_id, content, true
        )
        logger.log("Puppeteer page saved")
      else
        logger.log("Puppeteer page saved - canonical uri already seen")
      end
    end

    Page.new(link.canonical_uri, link.uri, start_link_id, content_type, content, document, is_puppeteer_used)
  elsif PERMANENT_ERROR_CODES.include?(resp.code)
    ctx.fetched_canonical_uris << link.canonical_uri
    storage.save_permanent_error(
      link.canonical_uri.to_s, link.url, start_link_id, resp.code
    )
    logger.log("#{resp.code} #{request_ms}ms #{link.url}")
    PermanentError.new(link.canonical_uri, link.url, start_link_id, resp.code)
  else
    raise "HTTP #{resp.code}" # TODO more cases here
  end
end

CLASS_SUBSTITUTIONS = {
  '/' => '%2F',
  '[' => '%5B',
  ']' => '%5D',
  '(' => '%28',
  ')' => '%29'
}

def extract_links(
  page, allowed_hosts, redirects, logger, include_xpath = false, include_class_xpath = false
)
  return [] unless page.document

  link_elements = page.document.xpath('//a').to_a +
    page.document.xpath('//link[@rel="next"]').to_a +
    page.document.xpath('//link[@rel="prev"]').to_a +
    page.document.xpath('//area').to_a
  links = []
  classes_by_xpath = {}
  link_elements.each do |element|
    link = html_element_to_link(
      element, page.fetch_uri, page.document, classes_by_xpath, redirects, logger, include_xpath,
      include_class_xpath
    )
    next if link.nil?
    if allowed_hosts.nil? || allowed_hosts.include?(link.uri.host)
      links << link
    end
  end

  links
end

def nokogiri_html5(content)
  html = Nokogiri::HTML5(content, max_attributes: -1, max_tree_depth: -1)
  html.remove_namespaces!
  html
end

def html_element_to_link(
  element, fetch_uri, document, classes_by_xpath, redirects, logger, include_xpath = false,
  include_class_xpath = false
)
  return nil unless element.attributes.key?('href')
  url_attribute = element.attributes['href']
  link = to_canonical_link(url_attribute.to_s, logger, fetch_uri)
  return nil if link.nil?
  link = follow_cached_redirects(link, redirects).clone
  link.element = element

  if include_xpath || include_class_xpath
    class_xpath = ""
    xpath = ""
    prefix_xpath = ""
    xpath_tokens = element.path.split('/')[1..-1]
    xpath_tokens.each do |token|
      bracket_index = token.index("[")

      if include_xpath
        if bracket_index
          xpath += "/#{token}"
        else
          xpath += "/#{token}[1]"
        end
      end

      if include_class_xpath
        prefix_xpath += "/#{token}"
        if classes_by_xpath.key?(prefix_xpath)
          classes = classes_by_xpath[prefix_xpath]
        else
          begin
            ancestor = document.at_xpath(prefix_xpath)
          rescue Nokogiri::XML::XPath::SyntaxError, NoMethodError => e
            logger.log("Invalid XPath on page #{fetch_uri}: #{prefix_xpath} has #{e}, skipping this link")
            return nil
          end
          ancestor_classes = ancestor.attributes['class']
          if ancestor_classes
            classes = classes_by_xpath[prefix_xpath] = ancestor_classes
              .value
              .split(' ')
              .map { |klass| klass.gsub(/[\/\[\]()]/, CLASS_SUBSTITUTIONS) }
              .sort
              .join(',')
          else
            classes = classes_by_xpath[prefix_xpath] = ''
          end
        end

        if bracket_index
          class_xpath += "/#{token[0...bracket_index]}(#{classes})#{token[bracket_index..-1]}"
        else
          class_xpath += "/#{token}(#{classes})[1]"
        end
      end
    end

    if include_xpath
      link.xpath = xpath
    end
    if include_class_xpath
      link.class_xpath = class_xpath
    end
  end
  link
end

def follow_cached_redirects(initial_link, redirects, seen_urls = nil)
  link = initial_link
  if seen_urls.nil?
    seen_urls = [link.url]
  end
  while redirects.key?(link.url) && link.url != redirects[link.url].url
    redirection_link = redirects[link.url]
    if seen_urls.include?(redirection_link.url)
      raise "Circular redirect for #{initial_link.url}: #{seen_urls} -> #{redirection_link.url}"
    end
    seen_urls << redirection_link.url
    link = redirection_link
  end
  link
end

ARCHIVES_REGEX = "/(?:archives?|posts?|all)(?:\\.[a-z]+)?/*$"
MAIN_PAGE_REGEX = "/(?:archives?|blog|posts?|articles|writing|journal|all)(?:\\.[a-z]+)?/*$"

def guided_crawl_loop(
  start_link_id, start_page, feed_entry_links, feed_generator, ctx, canonical_equality_cfg, mock_http_client,
  puppeteer_client, db_storage, gt_main_page_canonical_uri, logger
)
  start_page_links = extract_links(
    start_page, nil, ctx.redirects, logger, true, true
  )
  start_page_canonical_uris_set = start_page_links
    .map(&:canonical_uri)
    .to_canonical_uri_set(canonical_equality_cfg)
  feed_entry_canonical_uris = feed_entry_links.map(&:canonical_uri)
  feed_entry_canonical_uris_set = feed_entry_canonical_uris.to_canonical_uri_set(canonical_equality_cfg)
  pages_without_puppeteer = []

  does_start_page_path_match_archives = start_page.canonical_uri.path.match?(ARCHIVES_REGEX)
  if does_start_page_path_match_archives
    start_page_result = try_extract_historical(
      start_page, start_page_links, start_page_canonical_uris_set, feed_entry_links,
      feed_entry_canonical_uris, feed_entry_canonical_uris_set, feed_generator, canonical_equality_cfg,
      start_link_id, ctx, mock_http_client, db_storage, logger
    )

    return { best_result: start_page_result } if start_page_result
    logger.log("Start page matches archives regex but is not the main page")
    pages_without_puppeteer << start_page unless start_page.is_puppeteer_used
  else
    logger.log("Start page doesn't match archives regex")
  end

  logger.log("Trying select links from start page")

  allowed_hosts = canonical_equality_cfg.same_hosts.empty? ?
    [start_page.canonical_uri.host] :
    canonical_equality_cfg.same_hosts

  start_page_archives_links = start_page_links
    .filter { |link| allowed_hosts.include?(link.uri.host) && link.canonical_uri.path.match?(ARCHIVES_REGEX) }
  logger.log("Checking #{start_page_archives_links.length} archives links") unless start_page_archives_links.empty?
  start_page_archives_links_result, start_page_archives_pages_without_puppeteer = crawl_historical(
    start_page_archives_links, feed_entry_links, feed_entry_canonical_uris, feed_entry_canonical_uris_set,
    feed_generator, canonical_equality_cfg, start_link_id, ctx, mock_http_client, puppeteer_client,
    db_storage, logger
  )
  return { best_result: start_page_archives_links_result } if start_page_archives_links_result
  logger.log("Start page doesn't link to archives")
  pages_without_puppeteer.push(*start_page_archives_pages_without_puppeteer)

  unless does_start_page_path_match_archives
    start_page_result = try_extract_historical(
      start_page, start_page_links, start_page_canonical_uris_set, feed_entry_links,
      feed_entry_canonical_uris, feed_entry_canonical_uris_set, feed_generator, canonical_equality_cfg,
      start_link_id, ctx, mock_http_client, db_storage, logger
    )

    return { best_result: start_page_result } if start_page_result
    logger.log("Start page is not the main page")
    pages_without_puppeteer << start_page unless start_page.is_puppeteer_used
  end

  start_page_main_page_links = start_page_links
    .filter { |link| allowed_hosts.include?(link.uri.host) && link.canonical_uri.path.match?(MAIN_PAGE_REGEX) }
  logger.log("Checking #{start_page_main_page_links.length} main page links") unless start_page_main_page_links.empty?
  start_page_main_page_links_result, start_page_main_pages_without_puppeteer = crawl_historical(
    start_page_main_page_links, feed_entry_links, feed_entry_canonical_uris, feed_entry_canonical_uris_set,
    feed_generator, canonical_equality_cfg, start_link_id, ctx, mock_http_client, puppeteer_client,
    db_storage, logger
  )
  return { best_result: start_page_main_page_links_result } if start_page_main_page_links_result
  logger.log("Start page doesn't link to the main page")
  pages_without_puppeteer.push(*start_page_main_pages_without_puppeteer)

  logger.log("Trying common links from the first two entries")

  raise "Too few entries in feed: #{feed_entry_links.length}" if feed_entry_links.length < 2
  entry1_page = crawl_request(
    feed_entry_links[0], ctx, mock_http_client, nil, false, start_link_id,
    db_storage, logger
  )
  entry2_page = crawl_request(
    feed_entry_links[1], ctx, mock_http_client, nil, false, start_link_id,
    db_storage, logger
  )
  raise "Couldn't fetch entry 1: #{entry1_page}" unless entry1_page.is_a?(Page) && entry1_page.document
  raise "Couldn't fetch entry 2: #{entry2_page}" unless entry2_page.is_a?(Page) && entry2_page.document

  entry1_links = extract_links(
    entry1_page, allowed_hosts, ctx.redirects, logger, true, true
  )
  entry2_links = extract_links(
    entry2_page, allowed_hosts, ctx.redirects, logger, true, true
  )
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
  logger.log("Checking #{archives_links_from_both_entries.length} archives links") unless archives_links_from_both_entries.empty?
  archives_links_from_both_entries_result, archives_pages_without_puppeteer_from_both_entries = crawl_historical(
    archives_links_from_both_entries, feed_entry_links, feed_entry_canonical_uris,
    feed_entry_canonical_uris_set, feed_generator, canonical_equality_cfg, start_link_id, ctx,
    mock_http_client, puppeteer_client, db_storage, logger
  )
  return { best_result: archives_links_from_both_entries_result } if archives_links_from_both_entries_result
  logger.log("First two entries don't link to archives")
  pages_without_puppeteer.push(*archives_pages_without_puppeteer_from_both_entries)

  main_page_links_from_both_entries, other_links_from_both_entries = non_archives_links_from_both_entries
    .partition { |link| link.canonical_uri.path.match?(MAIN_PAGE_REGEX) }
  logger.log("Checking #{main_page_links_from_both_entries.length} main page links") unless main_page_links_from_both_entries.empty?
  main_page_links_from_both_entries_result, main_pages_without_puppeteer_from_both_entries = crawl_historical(
    main_page_links_from_both_entries, feed_entry_links, feed_entry_canonical_uris,
    feed_entry_canonical_uris_set, feed_generator, canonical_equality_cfg, start_link_id, ctx,
    mock_http_client, puppeteer_client, db_storage, logger
  )
  return { best_result: main_page_links_from_both_entries_result } if main_page_links_from_both_entries_result
  logger.log("First two entries don't link to the main page")
  pages_without_puppeteer.push(*main_pages_without_puppeteer_from_both_entries)

  logger.log("Checking #{other_links_from_both_entries.length} other links") unless other_links_from_both_entries.empty?
  # Don't put other pages in Puppeteer queue
  other_links_from_both_entries_result, _ = crawl_historical(
    other_links_from_both_entries, feed_entry_links, feed_entry_canonical_uris, feed_entry_canonical_uris_set,
    feed_generator, canonical_equality_cfg, start_link_id, ctx, mock_http_client, puppeteer_client,
    db_storage, logger
  )
  return { best_result: other_links_from_both_entries_result } if other_links_from_both_entries_result
  logger.log("First two entries don't link to something with a pattern")

  logger.log("Retrying #{pages_without_puppeteer.length} pages with Puppeteer")
  pages_without_puppeteer.each_with_index do |page, index|
    logger.log("#{index + 1}/#{pages_without_puppeteer.length} #{page.canonical_uri}")
    content, document = puppeteer_client.fetch(page.fetch_uri.to_s, ctx, logger)
    page_from_puppeteer = Page.new(
      page.canonical_uri, page.fetch_uri, page.start_link_id, page.content_type, content, document, true
    )

    if !ctx.pptr_fetched_canonical_uris.include?(page.canonical_uri)
      ctx.pptr_fetched_canonical_uris << page.canonical_uri
      db_storage.save_page(
        page.canonical_uri.to_s, page.fetch_uri.to_s, page.content_type, start_link_id, content, true
      )
      logger.log("Puppeteer page saved")
    else
      logger.log("Puppeteer page saved - canonical uri already seen")
    end

    page_from_puppeteer_links = extract_links(
      page_from_puppeteer, nil, ctx.redirects, logger, true, true
    )
    page_from_puppeteer_canonical_uris_set = page_from_puppeteer_links
      .map(&:canonical_uri)
      .to_canonical_uri_set(canonical_equality_cfg)
    puppeteer_result = try_extract_historical(
      page_from_puppeteer, page_from_puppeteer_links, page_from_puppeteer_canonical_uris_set,
      feed_entry_links, feed_entry_canonical_uris, feed_entry_canonical_uris_set, feed_generator,
      canonical_equality_cfg, start_link_id, ctx, mock_http_client, db_storage, logger
    )
    return { best_result: puppeteer_result } if puppeteer_result
  end

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
  links, feed_entry_links, feed_entry_canonical_uris, feed_entry_canonical_uris_set, feed_generator,
  canonical_equality_cfg, start_link_id, ctx, mock_http_client, puppeteer_client, db_storage, logger
)
  pages_without_puppeteer = []
  links.each do |link|
    next if ctx.fetched_canonical_uris.include?(link.canonical_uri)

    link_page = crawl_request(
      link, ctx, mock_http_client, puppeteer_client, false, start_link_id, db_storage, logger
    )
    unless link_page.is_a?(Page) && link_page.document
      logger.log("Couldn't fetch link: #{link_page}")
      next
    end
    pages_without_puppeteer << link_page unless link_page.is_puppeteer_used

    link_page_links = extract_links(
      link_page, nil, ctx.redirects, logger, true, true
    )
    link_page_canonical_uris_set = link_page_links
      .map(&:canonical_uri)
      .to_canonical_uri_set(canonical_equality_cfg)
    link_result = try_extract_historical(
      link_page, link_page_links, link_page_canonical_uris_set, feed_entry_links, feed_entry_canonical_uris,
      feed_entry_canonical_uris_set, feed_generator, canonical_equality_cfg, start_link_id, ctx,
      mock_http_client, db_storage, logger
    )

    return [link_result, []] if link_result
  end

  [nil, pages_without_puppeteer]
end

def try_extract_historical(
  page, page_links, page_canonical_uris_set, feed_entry_links, feed_entry_canonical_uris,
  feed_entry_canonical_uris_set, feed_generator, canonical_equality_cfg, start_link_id, ctx, mock_http_client,
  db_storage, logger
)
  paged_result = try_extract_paged(
    page, page_links, page_canonical_uris_set, feed_entry_canonical_uris, feed_entry_canonical_uris_set,
    feed_generator, canonical_equality_cfg, 1, start_link_id, ctx, mock_http_client, db_storage, logger
  )

  archives_result = try_extract_archives(
    page, page_links, page_canonical_uris_set, feed_entry_links, feed_entry_canonical_uris,
    feed_entry_canonical_uris_set, canonical_equality_cfg, 1, logger
  )

  if paged_result && archives_result
    if paged_result[:count] > archives_result[:count]
      paged_result
    else
      archives_result
    end
  elsif paged_result
    paged_result
  elsif archives_result
    archives_result
  end
end
