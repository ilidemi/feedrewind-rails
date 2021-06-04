require 'addressable/uri'
require 'net/http'
require 'nokogumbo'
require 'rss'
require 'set'
require_relative 'crawling_storage'
require_relative 'http_client'

CRAWLING_RESULT_COLUMNS = [
  [:start_url, :neutral],
  [:http_client_init_time, :neutral],
  [:feed_requests_made, :neutral],
  [:feed_time, :neutral],
  [:feed_url, :boolean],
  [:feed_links, :boolean],
  [:crawl_succeeded, :boolean],
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
    mock_db_storage = CrawlMockDbStorage.new(
      db, mock_http_client.page_fetch_urls, mock_http_client.permanent_error_fetch_urls,
      mock_http_client.redirect_fetch_urls
    )
    in_memory_storage = CrawlInMemoryStorage.new(mock_db_storage)
    page_links = crawl_loop(
      start_link_id, start_link[:host], [start_link], ctx, mock_http_client,
      :depth_1, nil, in_memory_storage, logger
    )

    raise "No outgoing links" if page_links.empty?

    prioritized_page_links = page_links.sort_by { |link| [calc_link_priority(link), link[:uri].path.length] }

    next_links = crawl_loop(
      start_link_id, start_link[:host], prioritized_page_links, ctx, mock_http_client,
      :depth_1_main_feed_fetched, nil, in_memory_storage, logger
    )

    result.feed_requests_made = ctx.requests_made
    result.feed_time = (monotonic_now - feed_start_time).to_i

    raise "Feed not found" if in_memory_storage.feeds.empty?

    feed_url = in_memory_storage.feeds.first[1][:canonical_url]
    result.feed_url = feed_url
    logger.log("Feed url: #{feed_url}")

    feed_page = in_memory_storage.pages[feed_url]
    feed = RSS::Parser.new(feed_page[:content]).parse
    feed_urls = extract_feed_urls(feed)
    result.feed_links = feed_urls.item_urls.length
    logger.log("Root url: #{feed_urls.root_url}")
    feed_page_fetch_uri = URI(feed_page[:fetch_url])

    item_canonical_urls = feed_urls.item_urls.map do |url|
      to_canonical_link(url, logger, feed_page_fetch_uri)[:canonical_url]
    end

    db.exec_params('delete from feeds where start_link_id = $1', [start_link_id])
    db.exec_params('delete from pages where start_link_id = $1', [start_link_id])
    db.exec_params('delete from permanent_errors where start_link_id = $1', [start_link_id])
    db.exec_params('delete from redirects where start_link_id = $1', [start_link_id])
    db_storage = CrawlDbStorage.new(db, mock_db_storage)
    save_to_db(in_memory_storage, db_storage)

    crawl_loop(
      start_link_id, start_link[:host], next_links, ctx, mock_http_client, :crawl_urls_vicinity,
      item_canonical_urls, db_storage, logger
    )
    result.crawl_succeeded = true

    items_found = item_canonical_urls.count { |url| ctx.seen_urls.include?(url) }
    result.items_found = items_found
    result.all_items_found = items_found == item_canonical_urls.length
    logger.log("Items found: #{items_found}/#{item_canonical_urls.length}")

    export_graph(db, start_link_id, start_link, feed_page_fetch_uri, feed_urls, logger)
    logger.log("Graph exported")

    result
  rescue => e
    raise CrawlingError.new(e.message, result), e
  ensure
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

FeedUrls = Struct.new(:root_url, :item_urls)

def extract_feed_urls(feed)
  if feed.is_a?(RSS::Rss)
    FeedUrls.new(
      feed.channel.link,
      feed.channel.items.map(&:link)
    )
  elsif feed.is_a?(RSS::Atom::Feed)
    root_link_candidates = feed.links.filter { |link| link.rel == 'alternate' }
    if root_link_candidates.empty?
      root_link_candidates = feed.links.filter { |link| link.rel.nil? }
    end
    raise "Not one candidate link: #{root_link_candidates.length}" if root_link_candidates.length != 1
    FeedUrls.new(
      root_link_candidates[0].href,
      feed.entries.map { |entry| entry.link.href }
    )
  else
    raise "Unknown feed type: #{feed.class}"
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

def export_graph(db, start_link_id, start_link, feed_uri, feed_urls, logger)
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

  def to_node_label(canonical_url)
    "/" + canonical_url.partition("/")[2]
  end

  def feed_url_to_node_label(feed_url, redirects, fetch_uri, logger)
    feed_link = to_canonical_link(feed_url, logger, fetch_uri)
    redirected_link = follow_redirects(feed_link, redirects)
    to_node_label(redirected_link[:canonical_url])
  end

  root_label = feed_url_to_node_label(feed_urls.root_url, redirects, feed_uri, logger)
  item_label_to_index = feed_urls
    .item_urls
    .map.with_index { |url, index| [feed_url_to_node_label(url, redirects, feed_uri, logger), index] }
    .to_h

  graph = pages.to_h do |canonical_url, page|
    [
      to_node_label(canonical_url),
      extract_links(page, start_link[:host], redirects, logger)
        .filter { |link| pages.key?(link[:canonical_url]) }
        .map { |link| to_node_label(link[:canonical_url]) }
    ]
  end

  start_link_label = to_node_label(start_link[:canonical_url])

  File.open("graph/#{start_link_id}.dot", "w") do |dot_f|
    dot_f.write("digraph G {\n")
    dot_f.write("    graph [overlap=false outputorder=edgesfirst]\n")
    dot_f.write("    node [style=filled fillcolor=white]\n")
    graph.each_key do |node|
      attributes = { "shape" => "box" }
      if node == start_link_label && node == root_label
        attributes["color"] = "orange"
      elsif node == start_link_label
        attributes["color"] = "yellow"
      elsif node == root_label
        attributes["color"] = "red"
      elsif item_label_to_index.key?(node)
        if item_label_to_index.length > 1
          spectrum_pos = item_label_to_index[node].to_f / (item_label_to_index.length - 1)
          green = (128 + (1.0 - spectrum_pos) * 127).to_i.to_s(16)
          blue = (128 + spectrum_pos * 127).to_i.to_s(16)
        else
          green = "ff"
          blue = "00"
        end
        attributes["color"] = "\"\#80#{green}#{blue}\""
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
  def initialize(ctx = nil)
    if ctx
      @seen_urls = ctx.seen_urls.clone
      @fetched_urls = ctx.fetched_urls.clone
      @redirects = ctx.redirects.clone
      @requests_made = ctx.requests_made
      @main_feed_fetched = ctx.main_feed_fetched
    else
      @seen_urls = Set.new
      @fetched_urls = Set.new
      @redirects = {}
      @requests_made = 0
      @main_feed_fetched = false
    end
  end

  attr_reader :seen_urls, :fetched_urls, :redirects
  attr_accessor :requests_made, :main_feed_fetched
end

PERMANENT_ERROR_CODES = %w[400 401 402 403 404 405 406 407 410 411 412 413 414 415 416 417 418 451]

def crawl_loop(
  start_link_id, host, start_links, ctx, http_client, early_stop_cond, vicinity_urls, storage, logger
)
  initial_seen_urls_count = ctx.seen_urls.length

  current_queue = queue1 = []
  next_queue = queue2 = []
  current_depth = 0
  start_links.each do |link|
    current_queue << link
    ctx.seen_urls << link[:canonical_url]
    logger.log("Enqueued #{link}")
  end

  vicinity_urls = Set.new(vicinity_urls)

  until current_queue.empty?
    if [:depth_1, :depth_1_main_feed_fetched].include?(early_stop_cond) && current_depth >= 1
      break
    end

    if early_stop_cond == :depth_1_main_feed_fetched && ctx.main_feed_fetched
      break
    end

    if ctx.seen_urls.length >= 3600
      raise "That's a lot of links. Is the blog really this big?"
    end

    link = current_queue.shift
    logger.log("Dequeued #{link}")
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

      page_links = extract_links(page, host, ctx.redirects, logger)
      is_page_missing_vicinity_links = early_stop_cond == :crawl_urls_vicinity &&
        !page_links.any? { |page_link| vicinity_urls.include?(page_link[:canonical_url]) }
      if is_page_missing_vicinity_links
        logger.log("Page doesn't contain any vicinity links")
      else
        page_links.each do |new_link|
          next if ctx.seen_urls.include?(new_link[:canonical_url])
          next_queue << new_link
          ctx.seen_urls << new_link[:canonical_url]
          logger.log("Enqueued #{new_link}")
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

      is_new_redirection = !ctx.seen_urls.include?(redirection_link[:canonical_url])
      is_redirection_not_fetched = link[:canonical_url] == redirection_link[:canonical_url] &&
        !ctx.fetched_urls.include?(link[:canonical_url])

      if is_new_redirection || is_redirection_not_fetched
        current_queue << redirection_link # Redirections go to the same queue
        ctx.seen_urls << redirection_link[:canonical_url]
        logger.log("Enqueued #{redirection_link}")
      end
    elsif PERMANENT_ERROR_CODES.include?(resp.code)
      content_type = 'permanent 4xx'
      ctx.fetched_urls << link[:canonical_url]
      storage.save_permanent_error(link[:canonical_url], link[:url], start_link_id, resp.code)
    else
      raise "HTTP #{resp.code}" # TODO more cases here
    end

    if current_queue.empty?
      temp_queue = current_queue
      current_queue = next_queue
      next_queue = temp_queue
      current_depth += 1
    end

    logger.log("total:#{ctx.seen_urls.length} fetched:#{ctx.fetched_urls.length} new:#{ctx.seen_urls.length - initial_seen_urls_count} queued:#{queue1.length + queue2.length} #{resp.code} #{content_type} #{request_ms}ms #{link[:url]}")
  end

  queue1 + queue2
end

def is_feed(page_content)
  begin
    !page_content.nil? && !!RSS::Parser.new(page_content).parse
  rescue
    false
  end
end

def extract_links(page, host, redirects, logger)
  if page[:content_type] != 'text/html'
    return []
  end

  document = Nokogiri::HTML5(page[:content], max_attributes: -1)
  link_elements = document.css('a').to_a + document.css('link').to_a
  links = []
  link_elements.each do |element|
    next unless element.attributes.key?('href')
    url_attribute = element.attributes['href']
    link = to_canonical_link(url_attribute.to_s, logger, page[:fetch_uri])
    next if link.nil? || link[:host] != host
    link = follow_redirects(link, redirects)
    link[:type] = element.attributes['type']
    links << link
  end

  links
end

def to_canonical_link(url, logger, fetch_uri = nil)
  begin
    url_stripped = url.strip
    url_newlines_removed = url_stripped.delete("\n")
    if %w[http:// https://].include?(url_newlines_removed)
      return nil
    end
    url_escaped = Addressable::URI.escape(url_newlines_removed)
    uri = URI(url_escaped)
  rescue Addressable::URI::InvalidURIError => e
    logger.log(e)
    return nil
  rescue => e
    raise e
  end

  if uri.scheme.nil? && uri.host.nil? && !fetch_uri.nil? # Relative uri
    fetch_uri_classes = { 'http' => URI::HTTP, 'https' => URI::HTTPS }
    path = URI::join(fetch_uri, uri).path
    uri = fetch_uri_classes[fetch_uri.scheme].build(host: fetch_uri.host, path: path, query: uri.query)
  end

  unless %w[http https].include? uri.scheme
    return nil
  end

  canonical_url = to_canonical_url(uri)
  uri.fragment = nil

  if uri.opaque != nil
    logger.log("Opaque URL: #{url} #{uri.opaque}")
    return nil
  end

  if uri.userinfo != nil || uri.registry != nil
    raise "URI has extra parts: #{uri}"
  end

  { canonical_url: canonical_url, host: uri.host, uri: uri, url: uri.to_s }
end

def to_canonical_url(uri)
  port_str = (
    uri.port.nil? || (uri.port == 80 && uri.scheme == 'http') || (uri.port == 443 && uri.scheme == 'https')
  ) ? '' : ":#{uri.port}"
  path_str = (uri.path == '/' && uri.query.nil?) ? '' : uri.path
  query_str = uri.query.nil? ? '' : "?#{uri.query}"
  "#{uri.host}#{port_str}#{path_str}#{query_str}" # drop scheme and fragment
end

def follow_redirects(link, redirects)
  while redirects.key?(link[:url]) && link != redirects[link[:url]]
    link = redirects[link[:url]]
  end
  link
end
