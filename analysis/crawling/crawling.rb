require 'addressable/uri'
require 'net/http'
require 'nokogumbo'
require 'rss'
require 'set'
require_relative 'crawling_storage'
require_relative 'feed_parsing'
require_relative 'http_client'

CRAWLING_RESULT_COLUMNS = [
  [:start_url, :neutral],
  [:http_client_init_time, :neutral],
  [:feed_requests_made, :neutral],
  [:feed_time, :neutral],
  [:feed_url, :boolean],
  [:feed_links, :boolean],
  [:crawl_succeeded, :boolean],
  [:duplicate_fetches, :neutral],
  [:items_found, :neutral],
  [:all_items_found, :boolean],
  [:total_requests, :neutral],
  [:total_pages, :neutral],
  [:total_network_requests, :neutral],
  [:total_time, :neutral]
]

class CrawlingResult
  @column_names = CRAWLING_RESULT_COLUMNS.map { |column| column[0].to_s.gsub("_", " ") }

  def initialize
    CRAWLING_RESULT_COLUMNS.each do |column|
      instance_variable_set("@#{column[0]}", nil)
    end
  end

  def column_values
    CRAWLING_RESULT_COLUMNS.map { |column| instance_variable_get("@#{column[0]}") }
  end

  def column_statuses
    CRAWLING_RESULT_COLUMNS.map do |column|
      if column[1] == :neutral
        :neutral
      elsif column[1] == :boolean
        instance_variable_get("@#{column[0]}") ? :success : :failure
      else
        raise "Unknown column status symbol: #{column[1]}"
      end
    end
  end

  class << self
    attr_reader :column_names
  end

  attr_writer *(CRAWLING_RESULT_COLUMNS.map { |column| column[0] })
end

class CrawlingError < StandardError
  def initialize(message, result)
    @result = result
    super(message)
  end

  attr_reader :result
end

def discover_feed(db, start_link_id, logger)
  start_link_url = db.exec_params('select url from start_links where id = $1', [start_link_id])[0]["url"]
  result = CrawlingResult.new
  result.start_url = start_link_url
  ctx = CrawlContext.new
  start_time = monotonic_now

  begin
    mock_http_client = MockHttpClient.new(db, start_link_id)
    result.http_client_init_time = (monotonic_now - start_time).to_i

    feed_start_time = monotonic_now
    start_link = to_canonical_link(start_link_url, logger)
    allowed_hosts = Set.new([start_link[:host]])
    mock_db_storage = CrawlMockDbStorage.new(
      db, mock_http_client.page_fetch_urls, mock_http_client.permanent_error_fetch_urls,
      mock_http_client.redirect_fetch_urls
    )
    in_memory_storage = CrawlInMemoryStorage.new(mock_db_storage)
    round1_links = crawl_loop(
      start_link_id, allowed_hosts, [start_link], ctx, mock_http_client,
      :depth_1, nil, in_memory_storage, logger
    )

    raise "No outgoing links" if round1_links[:allowed_host_links].empty?

    prioritized_page_links = round1_links[:allowed_host_links]
      .sort_by { |link| [calc_link_priority(link), link[:uri].path.length] }

    round2_links = crawl_loop(
      start_link_id, allowed_hosts, prioritized_page_links, ctx, mock_http_client,
      :depth_1_main_feed_fetched, nil, in_memory_storage, logger
    )

    result.feed_requests_made = ctx.requests_made
    result.feed_time = (monotonic_now - feed_start_time).to_i

    raise "Feed not found" if in_memory_storage.feeds.empty?

    feed_url = in_memory_storage.feeds.first[1][:canonical_url]
    result.feed_url = feed_url
    logger.log("Feed url: #{feed_url}")

    feed_page = in_memory_storage.pages[feed_url]
    feed_urls = extract_feed_urls(feed_page[:content])
    result.feed_links = feed_urls.item_urls.length
    logger.log("Root url: #{feed_urls.root_url}")
    feed_page_fetch_uri = URI(feed_page[:fetch_url])

    item_links = feed_urls.item_urls.map { |url| to_canonical_link(url, logger, feed_page_fetch_uri) }
    item_canonical_urls = item_links.map { |link| link[:canonical_url] }
    item_hosts = item_links.map { |link| link[:host] }
    allowed_hosts.merge(item_hosts)

    round3_start_links = round2_links[:allowed_host_links]
    round3_start_unique_urls = Set.new(round3_start_links.map { |link| link[:canonical_url] })
    round3_disallowed_host_start_links = round1_links[:disallowed_host_links] + round2_links[:disallowed_host_links]
    round3_disallowed_host_start_links.each do |link|
      next unless allowed_hosts.include?(link[:host])
      next if round3_start_unique_urls.include?(link[:canonical_url])
      round3_start_links << link
      round3_start_unique_urls << link[:canonical_url]
    end

    db.exec_params('delete from feeds where start_link_id = $1', [start_link_id])
    db.exec_params('delete from pages where start_link_id = $1', [start_link_id])
    db.exec_params('delete from permanent_errors where start_link_id = $1', [start_link_id])
    db.exec_params('delete from redirects where start_link_id = $1', [start_link_id])
    db_storage = CrawlDbStorage.new(db, mock_db_storage)
    save_to_db(in_memory_storage, db_storage)

    crawl_loop(
      start_link_id, allowed_hosts, round3_start_links, ctx, mock_http_client,
      :crawl_urls_vicinity, item_canonical_urls, db_storage, logger
    )
    result.crawl_succeeded = true

    items_found = item_canonical_urls.count { |url| ctx.seen_canonical_urls.include?(url) }
    result.items_found = items_found
    result.all_items_found = items_found == item_canonical_urls.length
    logger.log("Items found: #{items_found}/#{item_canonical_urls.length}")

    export_graph(db, start_link_id, start_link, allowed_hosts, feed_page_fetch_uri, feed_urls, logger)
    logger.log("Graph exported")

    result
  rescue => e
    raise CrawlingError.new(e.message, result), e
  ensure
    result.duplicate_fetches = ctx.duplicate_fetches
    result.total_requests = ctx.requests_made
    result.total_pages = ctx.fetched_urls.length
    result.total_network_requests = defined?(mock_http_client) && mock_http_client.network_requests_made
    result.total_time = (monotonic_now - start_time).to_i
  end
end

def calc_link_priority(link)
  if !link[:type].nil? && (link[:type].include?('rss') || link[:type].include?('atom'))
    -10
  elsif link[:uri].path.include?('rss') || link[:uri].path.include?('atom')
    -2
  elsif link[:uri].path.include?('feed')
    -1
  else
    0
  end
end

def save_to_db(in_memory_storage, db_storage)
  in_memory_storage.pages.each_value do |page|
    db_storage.save_page(page[:canonical_url], page[:fetch_url], page[:content_type], page[:start_link_id], page[:content])
  end

  in_memory_storage.redirects.each_value do |redirect|
    db_storage.save_redirect(redirect[:from_fetch_url], redirect[:to_fetch_url], redirect[:start_link_id])
  end

  in_memory_storage.permanent_errors.each_value do |permanent_error|
    db_storage.save_permanent_error(permanent_error[:canonical_url], permanent_error[:fetch_url], permanent_error[:start_link_id], permanent_error[:code])
  end

  in_memory_storage.feeds.each_value do |feed|
    db_storage.save_feed(feed[:start_link_id], feed[:canonical_url])
  end
end

def export_graph(db, start_link_id, start_link, allowed_hosts, feed_uri, feed_urls, logger)
  redirects = db
    .exec_params(
      'select from_fetch_url, to_fetch_url from redirects where start_link_id = $1',
      [start_link_id]
    )
    .to_h do |row|
    [row["from_fetch_url"], to_canonical_link(row["to_fetch_url"], logger)]
  end

  pages = db
    .exec_params(
      'select canonical_url, fetch_url, content_type, content from pages where start_link_id = $1',
      [start_link_id]
    )
    .to_h { |row| [row["canonical_url"], { fetch_uri: URI(row["fetch_url"]), content_type: row["content_type"], content: row["content"] }] }
    .filter { |_, page| !page[:content].nil? }

  def to_node_label(canonical_url, allowed_hosts)
    if allowed_hosts.length == 1
      "/" + canonical_url.partition("/")[2]
    else
      canonical_url
    end
  end

  def feed_url_to_node_label(feed_url, allowed_hosts, redirects, fetch_uri, logger)
    feed_link = to_canonical_link(feed_url, logger, fetch_uri)
    redirected_link = follow_redirects(feed_link, redirects)
    to_node_label(redirected_link[:canonical_url], allowed_hosts)
  end

  root_label = feed_url_to_node_label(feed_urls.root_url, allowed_hosts, redirects, feed_uri, logger)
  item_label_to_index = feed_urls
    .item_urls
    .map.with_index { |url, index| [feed_url_to_node_label(url, allowed_hosts, redirects, feed_uri, logger), index] }
    .to_h

  graph = pages.to_h do |canonical_url, page|
    [
      to_node_label(canonical_url, allowed_hosts),
      extract_links(page, allowed_hosts, redirects, logger)[:allowed_host_links]
        .filter { |link| pages.key?(link[:canonical_url]) }
        .map { |link| to_node_label(link[:canonical_url], allowed_hosts) }
    ]
  end

  start_link_label = to_node_label(start_link[:canonical_url], allowed_hosts)

  File.open("graph/#{start_link_id}.dot", "w") do |dot_f|
    dot_f.write("digraph G {\n")
    dot_f.write("    graph [overlap=false outputorder=edgesfirst]\n")
    dot_f.write("    node [style=filled fillcolor=white]\n")
    graph.each_key do |node|
      attributes = { "shape" => "box" }
      if node == start_link_label && node == root_label
        attributes["fillcolor"] = "orange"
      elsif node == start_link_label
        attributes["fillcolor"] = "yellow"
      elsif node == root_label
        attributes["fillcolor"] = "red"
      elsif item_label_to_index.key?(node)
        if item_label_to_index.length > 1
          spectrum_pos = item_label_to_index[node].to_f / (item_label_to_index.length - 1)
          green = (128 + (1.0 - spectrum_pos) * 127).to_i.to_s(16)
          blue = (128 + spectrum_pos * 127).to_i.to_s(16)
        else
          green = "ff"
          blue = "00"
        end
        attributes["fillcolor"] = "\"\#80#{green}#{blue}\""
      end
      attributes_str = attributes
        .map { |k, v| "#{k}=#{v}" }
        .to_a
        .join(", ")
      dot_f.write("    \"#{node}\" [#{attributes_str}]\n")
    end
    graph.each do |node1, node2s|
      filtered_node2s = item_label_to_index.key?(node1) ?
        node2s.filter { |node2| item_label_to_index.key?(node2) } :
        node2s
      filtered_node2s.each do |node2|
        dot_f.write("    \"#{node1}\" -> \"#{node2}\"\n")
      end
    end
    dot_f.write("}\n")
  end

  command_prefix = File.exist?("/dev/null") ? "" : "wsl "
  raise "Graph generation failed" unless system("#{command_prefix}sfdp -Tsvg graph/#{start_link_id}.dot > graph/#{start_link_id}.svg")
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
  end

  attr_reader :seen_canonical_urls, :seen_fetch_urls, :fetched_urls, :redirects
  attr_accessor :requests_made, :duplicate_fetches, :main_feed_fetched
end

PERMANENT_ERROR_CODES = %w[400 401 402 403 404 405 406 407 410 411 412 413 414 415 416 417 418 451]

def crawl_loop(
  start_link_id, allowed_hosts, start_links, ctx, http_client, early_stop_cond, vicinity_urls, storage, logger
)
  initial_seen_urls_count = ctx.seen_canonical_urls.length

  current_queue = queue1 = []
  next_queue = queue2 = []
  current_depth = 0
  start_links.each do |link|
    current_queue << link
    ctx.seen_canonical_urls << link[:canonical_url]
    ctx.seen_fetch_urls << link[:url]
    logger.log("Enqueued #{link}")
  end

  vicinity_urls = Set.new(vicinity_urls)
  disallowed_host_links = []

  until current_queue.empty?
    if [:depth_1, :depth_1_main_feed_fetched].include?(early_stop_cond) && current_depth >= 1
      break
    end

    if early_stop_cond == :depth_1_main_feed_fetched && ctx.main_feed_fetched
      break
    end

    if ctx.seen_canonical_urls.length >= 7200
      raise "That's a lot of links. Is the blog really this big?"
    end

    link = current_queue.shift
    logger.log("Dequeued #{link}")

    if ctx.fetched_urls.include?(link[:canonical_url])
      ctx.duplicate_fetches += 1
      resp_status = "duplicate url, already fetched"
    else
      request_start = monotonic_now
      resp = http_client.request(link[:uri], logger)
      request_ms = ((monotonic_now - request_start) * 1000).to_i
      ctx.requests_made += 1

      if resp.code == "200"
        content_type = resp.content_type.split(';')[0]
        is_main_feed = false
        if content_type == "text/html"
          content = resp.body
        elsif !ctx.main_feed_fetched && is_feed(resp.body)
          content = resp.body
          is_main_feed = true
        else
          content = nil
        end

        page = { fetch_uri: link[:uri], content_type: content_type, content: content }
        ctx.fetched_urls << link[:canonical_url]
        storage.save_page(link[:canonical_url], link[:url], content_type, start_link_id, content)
        if is_main_feed
          storage.save_feed(start_link_id, link[:canonical_url])
          ctx.main_feed_fetched = true
        end

        page_links = extract_links(page, allowed_hosts, ctx.redirects, logger)
        is_page_missing_vicinity_links = early_stop_cond == :crawl_urls_vicinity &&
          !page_links[:allowed_host_links].any? { |page_link| vicinity_urls.include?(page_link[:canonical_url]) }
        if is_page_missing_vicinity_links
          logger.log("Page doesn't contain any vicinity links")
        else
          page_links[:allowed_host_links].each do |new_link|
            next if ctx.seen_canonical_urls.include?(new_link[:canonical_url])
            next_queue << new_link
            ctx.seen_canonical_urls << new_link[:canonical_url]
            ctx.seen_fetch_urls << new_link[:url]
            logger.log("Enqueued #{new_link}")
          end
          page_links[:disallowed_host_links].each do |new_link|
            next if ctx.seen_canonical_urls.include?(new_link[:canonical_url])
            disallowed_host_links << new_link
            ctx.seen_canonical_urls << new_link[:canonical_url]
            ctx.seen_fetch_urls << new_link[:url]
          end
        end
      elsif resp.code.start_with?('3')
        content_type = 'redirect'
        redirection_url = resp.location
        redirection_link = to_canonical_link(redirection_url, logger, link[:uri])

        if link[:url] == redirection_link[:url]
          raise "Redirect to the same place, something's wrong"
        end

        ctx.redirects[link[:url]] = redirection_link
        storage.save_redirect(link[:url], redirection_link[:url], start_link_id)

        is_redirect_fetch_url_already_seen = ctx.seen_fetch_urls.include?(redirection_link[:url])
        # is_redirect_already_fetched = ctx.fetched_urls.include?(redirection_link[:canonical_url])

        if !is_redirect_fetch_url_already_seen # || !is_redirect_already_fetched
          current_queue << redirection_link # Redirections go to the same queue
          ctx.seen_canonical_urls << redirection_link[:canonical_url]
          ctx.seen_fetch_urls << redirection_link[:url]
          logger.log("Enqueued redirect #{redirection_link}")
        end
      elsif PERMANENT_ERROR_CODES.include?(resp.code)
        content_type = 'permanent 4xx'
        ctx.fetched_urls << link[:canonical_url]
        storage.save_permanent_error(link[:canonical_url], link[:url], start_link_id, resp.code)
      else
        raise "HTTP #{resp.code}" # TODO more cases here
      end
      resp_status = "#{resp.code} #{content_type} #{request_ms}ms"
    end

    if current_queue.empty?
      temp_queue = current_queue
      current_queue = next_queue
      next_queue = temp_queue
      current_depth += 1
    end

    logger.log("total:#{ctx.seen_canonical_urls.length} fetched:#{ctx.fetched_urls.length} new:#{ctx.seen_canonical_urls.length - initial_seen_urls_count} queued:#{queue1.length + queue2.length} disallowed:#{disallowed_host_links.length} #{resp_status} #{link[:url]}")
  end

  { allowed_host_links: queue1 + queue2, disallowed_host_links: disallowed_host_links }
end

def extract_links(page, allowed_hosts, redirects, logger)
  if page[:content_type] != 'text/html'
    return { allowed_host_links: [], disallowed_host_links: [] }
  end

  document = Nokogiri::HTML5(page[:content], max_attributes: -1)
  link_elements = document.css('a').to_a + document.css('link').to_a
  allowed_host_links = []
  disallowed_host_links = []
  link_elements.each do |element|
    next unless element.attributes.key?('href')
    url_attribute = element.attributes['href']
    link = to_canonical_link(url_attribute.to_s, logger, page[:fetch_uri])
    next if link.nil?
    link = follow_redirects(link, redirects)
    link[:type] = element.attributes['type']
    if allowed_hosts.include?(link[:host])
      allowed_host_links << link
    else
      disallowed_host_links << link
    end
  end

  { allowed_host_links: allowed_host_links, disallowed_host_links: disallowed_host_links }
end

def to_canonical_link(url, logger, fetch_uri = nil)
  url_stripped = url
    .sub(/\A( |\t|\n|\x00|\v|\f|\r|%20|%09|%0a|%00|%0b|%0c|%0d)+/i, '')
    .sub(/( |\t|\n|\x00|\v|\f|\r|%20|%09|%0a|%00|%0b|%0c|%0d)+\z/i, '')
  url_newlines_removed = url_stripped.delete("\n")

  if !/\A(http(s)?:)?[\-_.!~*'()a-zA-Z\d;\/?@&=+$,]+\z/.match?(url_newlines_removed)
    begin
      url_unescaped = Addressable::URI.unescape(url_newlines_removed)
      unless url_unescaped.valid_encoding?
        url_unescaped = url_newlines_removed
      end
      url_escaped = Addressable::URI.escape(url_unescaped)
    rescue Addressable::URI::InvalidURIError => e
      if e.message.include?("Invalid character in host") ||
        e.message.include?("Invalid port number") ||
        e.message.include?("Invalid scheme format") ||
        e.message.include?("Absolute URI missing hierarchical segment")

        logger.log("URL \"#{url}\" from \"#{fetch_uri}\" has #{e}")
        return nil
      else
        raise
      end
    end
  else
    url_escaped = url_newlines_removed
  end

  if url_escaped.start_with?("mailto:")
    return nil
  end

  uri = URI(url_escaped)

  if uri.scheme.nil? && uri.host.nil? && !fetch_uri.nil? # Relative uri
    fetch_uri_classes = { 'http' => URI::HTTP, 'https' => URI::HTTPS }
    path = URI::join(fetch_uri, uri).path
    uri = fetch_uri_classes[fetch_uri.scheme].build(host: fetch_uri.host, path: path, query: uri.query)
  end

  unless %w[http https].include? uri.scheme
    return nil
  end

  uri.fragment = nil
  if uri.userinfo != nil
    logger.log("URI \"#{uri}\" from \"#{fetch_uri}\" has userinfo: #{uri.userinfo}")
    return nil
  end
  if uri.opaque != nil
    logger.log("URI \"#{uri}\" from \"#{fetch_uri}\" has opaque: #{uri.opaque}")
    return nil
  end
  if uri.registry != nil
    raise "URI has extra parts: #{uri} registry:#{uri.registry}"
  end

  canonical_url = to_canonical_url(uri)
  { canonical_url: canonical_url, host: uri.host, uri: uri, url: uri.to_s }
end

WHITELISTED_QUERY_PARAMS = Set.new(%w[blog page year offset skip sort order format])

def to_canonical_url(uri)
  port_str = (
    uri.port.nil? || (uri.port == 80 && uri.scheme == 'http') || (uri.port == 443 && uri.scheme == 'https')
  ) ? '' : ":#{uri.port}"
  path_str = (uri.path == '/' && uri.query.nil?) ? '' : uri.path

  if uri.query
    whitelisted_query = uri
      .query
      .split("&")
      .map { |token| token.partition("=") }
      .filter { |param, _, _| WHITELISTED_QUERY_PARAMS.include?(param) }
      .map { |param, equals, value| equals.empty? ? param : value.empty? ? "#{param}=" : "#{param}=#{value}" }
      .join("&")
    query_str = whitelisted_query.empty? ? '' : "?#{whitelisted_query}"
  else
    query_str = ''
  end

  "#{uri.host}#{port_str}#{path_str}#{query_str}" # drop scheme and fragment too
end

def follow_redirects(link, redirects)
  while redirects.key?(link[:url]) && link != redirects[link[:url]]
    link = redirects[link[:url]]
  end
  link
end
