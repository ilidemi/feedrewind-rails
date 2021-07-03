require 'addressable/uri'
require 'nokogumbo'
require 'set'
require_relative 'crawling_storage'
require_relative 'export_graph'
require_relative 'feed_parsing'
require_relative 'historical'
require_relative 'http_client'
require_relative 'run_common'
require_relative 'structs'

CRAWLING_RESULT_COLUMNS = [
  [:start_url, :neutral],
  [:comment, :neutral],
  [:gt_pattern, :neutral],
  [:feed_requests_made, :neutral],
  [:feed_time, :neutral],
  [:feed_url, :boolean],
  [:feed_links, :boolean],
  [:crawl_succeeded, :boolean],
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

class CrawlRunnable
  def initialize
    @result_column_names = to_column_names(CRAWLING_RESULT_COLUMNS)
  end

  def run(start_link_id, save_successes, db, logger)
    crawl(start_link_id, save_successes, db, logger)
  end

  attr_reader :result_column_names
end

def crawl(start_link_id, save_successes, db, logger)
  start_link_row = db.exec_params('select url, rss_url from start_links where id = $1', [start_link_id])[0]
  start_link_url = start_link_row["url"]
  start_link_feed_url = start_link_row["rss_url"]
  result = RunResult.new(CRAWLING_RESULT_COLUMNS)
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

    mock_http_client = MockHttpClient.new(db, start_link_id)
    mock_db_storage = CrawlMockDbStorage.new(
      db, mock_http_client.page_fetch_urls, mock_http_client.permanent_error_fetch_urls,
      mock_http_client.redirect_fetch_urls
    )
    db.exec_params('delete from feeds where start_link_id = $1', [start_link_id])
    db.exec_params('delete from pages where start_link_id = $1', [start_link_id])
    db.exec_params('delete from permanent_errors where start_link_id = $1', [start_link_id])
    db.exec_params('delete from redirects where start_link_id = $1', [start_link_id])
    db.exec_params('delete from historical where start_link_id = $1', [start_link_id])
    db_storage = CrawlDbStorage.new(db, mock_db_storage)

    feed_start_time = monotonic_now
    crawl_start_pages = []
    if start_link_feed_url
      feed_link = to_canonical_link(start_link_feed_url, logger)
      raise "Bad feed link: #{start_link_feed_url}" if feed_link.nil?
    else
      start_link = to_canonical_link(start_link_url, logger)
      raise "Bad start link: #{start_link_url}" if start_link.nil?

      ctx.allowed_hosts << start_link.uri.host
      start_result = crawl_request(
        start_link, ctx, mock_http_client, false, start_link_id, db_storage, logger
      )
      raise "Unexpected start result: #{start_result}" unless start_result.is_a?(Page) && start_result.content

      ctx.seen_canonical_urls << start_result.canonical_url
      ctx.seen_fetch_urls << start_result.fetch_uri.to_s
      start_page = start_result
      crawl_start_pages << start_page
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
    result.feed_url = "<a href=\"#{feed_link.url}\">#{feed_link.canonical_url}</a>"
    ctx.allowed_hosts << feed_link.uri.host
    feed_result = crawl_request(
      feed_link, ctx, mock_http_client, true, start_link_id, db_storage, logger
    )
    raise "Unexpected feed result: #{feed_result}" unless feed_result.is_a?(Page) && feed_result.content

    feed_page = feed_result
    ctx.seen_canonical_urls << feed_page.canonical_url
    ctx.seen_fetch_urls << feed_page.fetch_uri.to_s
    db_storage.save_feed(start_link_id, feed_page.canonical_url)
    result.feed_requests_made = ctx.requests_made
    result.feed_time = (monotonic_now - feed_start_time).to_i
    logger.log("Feed url: #{feed_page.canonical_url}")

    feed_urls = extract_feed_urls(feed_page.content, logger)
    result.feed_links = feed_urls.item_urls.length
    logger.log("Root url: #{feed_urls.root_url}")
    logger.log("Items in feed: #{feed_urls.item_urls.length}")

    root_links = []
    if feed_urls.root_url
      root_link = to_canonical_link(feed_urls.root_url, logger, feed_page.fetch_uri)
      ctx.allowed_hosts << root_link.uri.host
      root_links << root_link
    end
    item_links = feed_urls
      .item_urls
      .map { |url| to_canonical_link(url, logger, feed_page.fetch_uri) }
    item_links.each do |link|
      ctx.allowed_hosts << link.uri.host
    end
    crawl_start_links = (item_links + root_links).uniq { |link| link.canonical_url }
    begin
      crawl_loop(
        start_link_id, crawl_start_links, crawl_start_pages, ctx, mock_http_client, db_storage, logger
      )
      result.crawl_succeeded = true
      rescue => e
        logger.log("Crawl threw: #{e}")
        result.crawl_succeeded = false
    end

    # TODO make it work when I need the graph the next time
    # export_graph(db, start_link_id, start_link, allowed_hosts, feed_page_fetch_uri, feed_urls, logger)

    item_canonical_urls = item_links
      .map { |link| follow_cached_redirects(link, ctx.redirects) }
      .map(&:canonical_url)
    historical_links = discover_historical_entries(
      start_link_id, feed_page.canonical_url, item_canonical_urls, ctx.redirects, db, logger
    )
    result.historical_links_found = !!historical_links
    raise "Historical links not found" unless historical_links

    entries_count = historical_links[:links].length
    oldest_link = historical_links[:links][-1]
    logger.log("Historical links: #{entries_count}")
    historical_links[:links].each do |historical_link|
      logger.log(historical_link.url)
    end

    db.exec_params(
      "insert into historical (start_link_id, pattern, entries_count, main_page_canonical_url, oldest_entry_canonical_url) values ($1, $2, $3, $4, $5)",
      [start_link_id, historical_links[:pattern], entries_count, historical_links[:main_canonical_url], oldest_link.canonical_url]
    )

    if gt_row
      historical_links_matching = true

      if historical_links[:pattern] == gt_row["pattern"]
        result.historical_links_pattern_status = :success
        result.historical_links_pattern = historical_links[:pattern]
      else
        result.historical_links_pattern_status = :failure
        result.historical_links_pattern = "#{historical_links[:pattern]} (#{gt_row["pattern"]})"
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
      if gt_main_url == historical_links[:main_canonical_url]
        result.main_url = "<a href=\"#{historical_links[:main_fetch_url]}\">#{historical_links[:main_canonical_url]}</a>"
      else
        result.main_url = "<a href=\"#{historical_links[:main_fetch_url]}\">#{historical_links[:main_canonical_url]}</a><br>(#{gt_row["main_page_canonical_url"]})"
      end

      gt_oldest_canonical_url = gt_row["oldest_entry_canonical_url"]
      if gt_oldest_canonical_url != oldest_link.canonical_url
        historical_links_matching = false
        result.oldest_link_status = :failure
        result.oldest_link = "<a href=\"#{oldest_link.url}\">#{oldest_link.canonical_url}</a><br>(#{gt_oldest_canonical_url})"
      else
        result.oldest_link_status = :success
        result.oldest_link = "<a href=\"#{oldest_link.url}\">#{oldest_link.canonical_url}</a>"
      end

      result.historical_links_matching = historical_links_matching

      has_succeeded_before = db
        .exec_params("select count(*) from successes where start_link_id = $1", [start_link_id])
        .first["count"]
        .to_i == 1
      if has_succeeded_before
        result.no_regression = historical_links_matching
        result.no_regression_status = historical_links_matching ? :success : :failure
      end

      if save_successes && !has_succeeded_before && historical_links_matching
        logger.log("First success for this id, saving")
        db.exec_params("insert into successes (start_link_id, timestamp) values ($1, now())", [start_link_id])
      end
    else
      result.historical_links_matching = '?'
      result.historical_links_matching_status = :neutral
      result.no_regression_status = :neutral
      result.historical_links_pattern = historical_links[:pattern]
      result.historical_links_count = entries_count
      result.main_url = "<a href=\"#{historical_links[:main_fetch_url]}\">#{historical_links[:main_canonical_url]}</a>"
      result.oldest_link = "<a href=\"#{oldest_link.url}\">#{oldest_link.canonical_url}</a>"
    end

    result.extra = historical_links[:extra]

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

class CrawlContext
  def initialize
    @seen_canonical_urls = Set.new
    @seen_fetch_urls = Set.new
    @fetched_urls = Set.new
    @redirects = {}
    @requests_made = 0
    @duplicate_fetches = 0
    @main_feed_fetched = false
    @allowed_hosts = Set.new
  end

  attr_reader :seen_canonical_urls, :seen_fetch_urls, :fetched_urls, :redirects, :allowed_hosts
  attr_accessor :requests_made, :duplicate_fetches, :main_feed_fetched
end

def crawl_loop(
  start_link_id, start_links, start_pages, ctx, http_client, storage, logger
)
  logger.log("Starting crawl loop for #{start_link_id} with #{start_links.length} links and #{start_pages.length} pages")
  initial_seen_urls_count = ctx.seen_canonical_urls.length

  queue = []
  start_links.each do |link|
    queue << link
    ctx.seen_canonical_urls << link.canonical_url
    ctx.seen_fetch_urls << link.url
    logger.log("Enqueued #{link}")
  end
  start_pages.each do |page|
    crawl_process_page_links(page, ctx.allowed_hosts, queue, ctx, logger)
  end

  until queue.empty?
    if (ctx.fetched_urls.length + queue.length) >= 7200
      raise "That's a lot of links. Is the blog really this big?"
    end

    link = queue.shift
    logger.log("Dequeued #{link}")

    if ctx.fetched_urls.include?(link.canonical_url)
      ctx.duplicate_fetches += 1
      logger.log("Duplicate url, already fetched: #{link.url}")
    else
      request_result = crawl_request(
        link, ctx, http_client, false, start_link_id, storage, logger
      )
      if request_result.is_a?(Page)
        crawl_process_page_links(request_result, ctx.allowed_hosts, queue, ctx, logger)
      elsif request_result.is_a?(PermanentError)
        # Do nothing
      elsif request_result.is_a?(AlreadySeenLink)
        # Do nothing
      elsif request_result.is_a?(BadRedirection)
        # Do nothing
      else
        raise "Unknown request result: #{request_result}"
      end
    end

    logger.log("total:#{ctx.fetched_urls.length + queue.length} fetched:#{ctx.fetched_urls.length} new:#{ctx.seen_canonical_urls.length - initial_seen_urls_count} queued:#{queue.length} seen:#{ctx.seen_canonical_urls.length} requests:#{ctx.requests_made}")
  end

  logger.log("Crawl loop done")
end

PERMANENT_ERROR_CODES = %w[400 401 402 403 404 405 406 407 410 411 412 413 414 415 416 417 418 451]

AlreadySeenLink = Struct.new(:link)
BadRedirection = Struct.new(:url)

def crawl_request(initial_link, ctx, http_client, is_feed_expected, start_link_id, storage, logger)
  link = initial_link
  seen_urls = [link.url]
  link = follow_cached_redirects(link, ctx.redirects, seen_urls)
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
      ctx.fetched_urls.include?(redirection_link.canonical_url)

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
    if content_type == "text/html" || (is_feed_expected && is_feed(resp.body, logger))
      content = resp.body
    else
      content = nil
    end
    ctx.fetched_urls << link.canonical_url
    storage.save_page(
      link.canonical_url, link.url, content_type, start_link_id, content
    )
    logger.log("#{resp.code} #{content_type} #{request_ms}ms #{link.url}")
    Page.new(link.canonical_url, link.uri, start_link_id, content_type, content)
  elsif PERMANENT_ERROR_CODES.include?(resp.code)
    ctx.fetched_urls << link.canonical_url
    storage.save_permanent_error(
      link.canonical_url, link.url, start_link_id, resp.code
    )
    logger.log("#{resp.code} #{request_ms}ms #{link.url}")
    PermanentError.new(link.canonical_url, link.url, start_link_id, resp.code)
  else
    raise "HTTP #{resp.code}" # TODO more cases here
  end
end

def crawl_process_page_links(page, allowed_hosts, queue, ctx, logger)
  page_links = extract_links(page, allowed_hosts, ctx.redirects, logger)
  page_links.each do |new_link|
    next if ctx.seen_canonical_urls.include?(new_link.canonical_url)
    queue << new_link
    ctx.seen_canonical_urls << new_link.canonical_url
    ctx.seen_fetch_urls << new_link.url
    logger.log("Enqueued #{new_link}")
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
  return [] unless page.content_type == 'text/html'

  document = nokogiri_html5(page.content)
  link_elements = document.xpath('//a').to_a +
    document.xpath('//link').to_a +
    document.xpath('//area').to_a
  links = []
  classes_by_xpath = {}
  link_elements.each do |element|
    link = html_element_to_link(
      element, page.fetch_uri, document, classes_by_xpath, redirects, logger, include_xpath,
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
  link.type = element.attributes['type']

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

def to_canonical_link(url, logger, fetch_uri = nil)
  url_stripped = url
    .sub(/\A( |\t|\n|\x00|\v|\f|\r|%20|%09|%0a|%00|%0b|%0c|%0d)+/i, '')
    .sub(/( |\t|\n|\x00|\v|\f|\r|%20|%09|%0a|%00|%0b|%0c|%0d)+\z/i, '')
  url_newlines_removed = url_stripped.delete("\n")

  if !/\A(http(s)?:)?[\-_.!~*'()a-zA-Z\d;\/?&=+$,]+\z/.match?(url_newlines_removed)
    begin
      url_unescaped = Addressable::URI.unescape(url_newlines_removed)
      unless url_unescaped.valid_encoding?
        url_unescaped = url_newlines_removed
      end
      return nil if url_unescaped.start_with?(":")
      url_escaped = Addressable::URI.escape(url_unescaped)
    rescue Addressable::URI::InvalidURIError => e
      if e.message.include?("Invalid character in host") ||
        e.message.include?("Invalid port number") ||
        e.message.include?("Invalid scheme format") ||
        e.message.include?("Absolute URI missing hierarchical segment")

        logger.log("Invalid URL: \"#{url}\" from \"#{fetch_uri}\" has #{e}")
        return nil
      else
        raise
      end
    end
  else
    url_escaped = url_newlines_removed
  end

  return nil if url_escaped.start_with?("mailto:")

  begin
    uri = URI(url_escaped)
  rescue URI::InvalidURIError => e
    logger.log("Invalid URL: \"#{url}\" from \"#{fetch_uri}\" has #{e}")
    return nil
  end

  if uri.scheme.nil? && !fetch_uri.nil? # Relative uri
    fetch_uri_classes = { 'http' => URI::HTTP, 'https' => URI::HTTPS }
    path = URI::join(fetch_uri, uri).path
    uri = fetch_uri_classes[fetch_uri.scheme].build(host: fetch_uri.host, path: path, query: uri.query)
  end

  return nil unless %w[http https].include? uri.scheme

  uri.fragment = nil
  if uri.userinfo != nil
    logger.log("Invalid URL: \"#{uri}\" from \"#{fetch_uri}\" has userinfo: #{uri.userinfo}")
    return nil
  end
  if uri.opaque != nil
    logger.log("Invalid URL: \"#{uri}\" from \"#{fetch_uri}\" has opaque: #{uri.opaque}")
    return nil
  end
  if uri.registry != nil
    raise "URI has extra parts: #{uri} registry:#{uri.registry}"
  end

  uri.path = uri.path.gsub("//", "/")
  uri.query = uri.query&.gsub("+", "%2B")

  canonical_url = to_canonical_url(uri)
  Link.new(canonical_url, uri, uri.to_s)
end

WHITELISTED_QUERY_PARAMS = Set.new(
  [
    "page",
    "year",
    "m", # month, apenwarr
    "start",
    "offset",
    "skip",
    "updated-max", # blogspot
    "sort",
    "order",
    "format"
  ]
)

WHITELISTED_QUERY_PARAM_REGEX = /.*page/ # freshpaint

def to_canonical_url(uri)
  port_str = (
    uri.port.nil? || (uri.port == 80 && uri.scheme == 'http') || (uri.port == 443 && uri.scheme == 'https')
  ) ? '' : ":#{uri.port}"

  if uri.path == '/' && uri.query.nil?
    path_str = ''
  else
    path_str = uri.path
  end

  if uri.query
    whitelisted_query = uri
      .query
      .split("&")
      .map { |token| token.partition("=") }
      .filter { |param, _, _| WHITELISTED_QUERY_PARAMS.include?(param) || WHITELISTED_QUERY_PARAM_REGEX.match?(param) }
      .map { |param, equals, value| equals.empty? ? param : value.empty? ? "#{param}=" : "#{param}=#{value}" }
      .join("&")
    query_str = whitelisted_query.empty? ? '' : "?#{whitelisted_query}"
  else
    query_str = ''
  end

  "#{uri.host}#{port_str}#{path_str}#{query_str}" # drop scheme and fragment too
end

def follow_cached_redirects(initial_link, redirects, seen_urls = nil)
  link = initial_link
  if seen_urls.nil?
    seen_urls = [link.url]
  end
  while redirects.key?(link.url) && link != redirects[link.url]
    redirection_link = redirects[link.url]
    if seen_urls.include?(redirection_link.url)
      raise "Circular redirect for #{initial_link.url}: #{seen_urls} -> #{redirection_link.url}"
    end
    seen_urls << redirection_link.url
    link = redirection_link
  end
  link
end
