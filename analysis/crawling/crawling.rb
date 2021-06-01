require 'addressable/uri'
require 'net/http'
require 'nokogumbo'
require 'rss'
require 'set'
require_relative 'canonical_url'
require_relative 'crawling_storage'
require_relative 'http_client'

CRAWLING_RESULT_COLUMN_NAMES = ['start url', 'http client init time', 'feed requests', 'feed time', 'feed url', 'feed links extracted', 'feed root url', 'feed channel prefixes items', 'crawl succeeded', 'total requests', 'total pages', 'total time']

class CrawlingResult
  def initialize(start_url)
    @start_url = start_url
    @http_client_init_time = nil
    @feed_requests_made = nil
    @feed_time = nil
    @feed_url = nil
    @feed_links_extracted = nil
    @feed_root_url = nil
    @feed_does_channel_prefix_items = nil
    @crawl_succeeded = nil
    @total_requests = nil
    @total_pages = nil
    @total_time = nil
  end

  def column_values
    [@start_url, @http_client_init_time, @feed_requests_made, @feed_time, @feed_url, @feed_links_extracted, @feed_root_url, @feed_does_channel_prefix_items, @crawl_succeeded, @total_requests, @total_pages, @total_time]
  end

  def column_statuses
    [
      :neutral,
      :neutral,
      :neutral,
      :neutral,
      @feed_url.nil? ? :failure : :success,
      @feed_links_extracted ? :success : :failure,
      @feed_root_url.nil? ? :failure : :success,
      @feed_does_channel_prefix_items ? :success : :failure,
      @crawl_succeeded ? :success : :failure,
      :neutral,
      :neutral,
      :neutral
    ]
  end

  attr_reader :column_names
  attr_writer :http_client_init_time, :feed_requests_made, :feed_time, :feed_url, :feed_links_extracted,
              :feed_root_url, :feed_does_channel_prefix_items, :crawl_succeeded, :total_requests,
              :total_pages, :total_time
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
  result = CrawlingResult.new(start_link_url)
  ctx = CrawlContext.new
  start_time = monotonic_now

  begin
    http_client = MockHttpClient.new(db, start_link_id)
    result.http_client_init_time = (monotonic_now - start_time).to_i

    feed_start_time = monotonic_now
    start_link = canonicalize_url(start_link_url, logger)
    in_memory_storage = CrawlInMemoryStorage.new
    page_links = crawl_loop(
      start_link_id, start_link[:host], '', [start_link], ctx, http_client,
      :depth_1, in_memory_storage, logger
    )

    raise "No outgoing links" if page_links.empty?

    prioritized_page_links = page_links.sort_by { |link| [calc_link_priority(link), link[:uri].path.length] }

    next_links = crawl_loop(
      start_link_id, start_link[:host], '', prioritized_page_links, ctx, http_client,
      :depth_1_main_feed_fetched, in_memory_storage, logger
    )

    result.feed_requests_made = ctx.requests_made
    result.feed_time = (monotonic_now - feed_start_time).to_i

    raise "Feed not found" if in_memory_storage.feeds.empty?

    feed_url = in_memory_storage.feeds.first[1][:canonical_url]
    result.feed_url = feed_url
    logger.log("Feed url: #{feed_url}")

    feed_content = in_memory_storage.pages[feed_url][:content]
    feed_feed = RSS::Parser.new(feed_content).parse
    feed_urls = extract_feed_urls(feed_feed)
    result.feed_links_extracted = true
    logger.log("Root url: #{feed_urls.root_url}")
    path_prefix = URI(feed_urls.root_url).path
    result.feed_root_url = path_prefix

    does_channel_prefix_items = feed_urls.item_urls.all? { |url| URI(url).path.start_with?(path_prefix) }
    result.feed_does_channel_prefix_items = does_channel_prefix_items
    logger.log("Channel prefixes items: #{does_channel_prefix_items}")
    raise "Channel doesn't prefix items" unless does_channel_prefix_items

    db.exec_params('delete from feeds where start_link_id = $1', [start_link_id])
    db.exec_params('delete from pages where start_link_id = $1', [start_link_id])
    db.exec_params('delete from permanent_errors where start_link_id = $1', [start_link_id])
    db.exec_params('delete from redirects where start_link_id = $1', [start_link_id])
    db_storage = CrawlDbStorage.new(db)
    save_to_db(in_memory_storage, db_storage, path_prefix)

    filtered_next_links = next_links.filter { |link| link[:uri].path.start_with?(path_prefix) }

    crawl_loop(
      start_link_id, start_link[:host], path_prefix, filtered_next_links, ctx, http_client,
      :no_early_stop, db_storage, logger
    )

    result.crawl_succeeded = true

    result
  rescue => e
    raise CrawlingError.new(e.message, result)
  ensure
    result.total_requests = ctx.requests_made
    result.total_pages = ctx.fetched_urls.length
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

def save_to_db(in_memory_storage, db_storage, path_prefix)
  in_memory_storage.pages.each_value do |page|
    next unless URI(page[:fetch_url]).path.start_with?(path_prefix)
    db_storage.save_page(page[:canonical_url], page[:fetch_url], page[:content_type], page[:start_link_id], page[:content])
  end

  in_memory_storage.redirects.each_value do |redirect|
    next unless URI(redirect[:to_fetch_url]).path.start_with?(path_prefix)
    db_storage.save_redirect(redirect[:from_canonical_url], redirect[:to_canonical_url], redirect[:to_fetch_url], redirect[:start_link_id])
  end

  in_memory_storage.permanent_errors.each_value do |permanent_error|
    next unless URI(permanent_error[:fetch_url]).path.start_with?(path_prefix)
    db_storage.save_permanent_error(permanent_error[:canonical_url], permanent_error[:fetch_url], permanent_error[:start_link_id], permanent_error[:code])
  end

  in_memory_storage.feeds.each_value do |feed|
    db_storage.save_feed(feed[:start_link_id], feed[:canonical_url])
  end
end

def export_graph(db, start_link_id, logger)
  start_link_url = db.exec_params('select url from start_links where id = $1', [start_link_id])[0]["url"]
  start_link = canonicalize_url(start_link_url, logger)

  redirects = db
    .exec_params(
      'select from_canonical_url, to_canonical_url, to_fetch_url from redirects where start_link_id = $1',
      [start_link_id]
    )
    .to_h do |row|
    fetch_uri = URI(row["to_fetch_url"])
    [row["from_canonical_url"], { canonical_url: row["to_canonical_url"], uri: fetch_uri, host: fetch_uri.host }]
  end

  pages = db
    .exec_params(
      'select canonical_url, fetch_url, content_type, content from pages where start_link_id = $1',
      [start_link_id]
    )
    .to_h { |row| [row["canonical_url"], { fetch_uri: URI(row["fetch_url"]), content_type: row["content_type"], content: row["content"] }] }
    .filter { |_, page| !page[:content].nil? }

  feed_canonical_url = db.exec_params('select canonical_url from feeds where start_link_id = $1', [start_link_id])[0]["canonical_url"]
  feed_content = pages[feed_canonical_url][:content]
  feed = RSS::Parser.new(feed_content).parse
  feed_urls = extract_feed_urls(feed)
  path_prefix = URI(feed_urls.root_url).path

  def to_node_label(canonical_url, path_prefix)
    path = "/" + canonical_url.partition("/")[2]
    path.sub("^#{path_prefix}", "")
  end

  graph = pages.to_h do |canonical_url, page|
    [
      to_node_label(canonical_url, path_prefix),
      extract_links(page, start_link[:host], path_prefix, redirects, logger)
        .filter { |link| pages.key?(link[:canonical_url]) }
        .map { |link| to_node_label(link[:canonical_url], path_prefix) }
    ]
  end

  start_link_label = to_node_label(start_link[:canonical_url], path_prefix)

  File.open("graph/#{start_link_id}.dot", "w") do |dot_f|
    dot_f.write("digraph G {\n")
    graph.each_key do |node|
      attributes = node == start_link_label ? " [shape=box, color=orange, style=filled]" : " [shape=box]"
      dot_f.write("    \"#{node}\"#{attributes}\n")
    end
    graph.each do |node1, node2s|
      node2s.each do |node2|
        dot_f.write("    \"#{node1}\" -> \"#{node2}\"\n")
      end
    end
    dot_f.write("}\n")
  end

  raise "Graph generation failed" unless system("wsl neato -Goverlap=false -Tsvg graph/#{start_link_id}.dot > graph/#{start_link_id}.svg")
end

def start_crawl(db, start_link_id, logger)
  start_link_url = db.exec_params('select url from start_links where id = $1', [start_link_id])[0]["url"]
  start_link = canonicalize_url(start_link_url, logger)

  redirects = db
    .exec_params(
      'select from_canonical_url, to_canonical_url, to_fetch_url from redirects where start_link_id = $1',
      [start_link_id]
    )
    .map do |row|
    fetch_uri = URI(row["to_fetch_url"])
    [row["from_canonical_url"], { canonical_url: row["to_canonical_url"], uri: fetch_uri, host: fetch_uri.host }]
  end
    .to_h

  pages = db
    .exec_params(
      'select canonical_url, fetch_url, content_type, content from pages where start_link_id = $1',
      [start_link_id]
    )
    .map { |row| [row["canonical_url"], { fetch_uri: URI(row["fetch_url"]), content_type: row["content_type"], content: row["content"] }] }
    .to_h

  pages_links = pages
    .map { |_, page| extract_links(page, start_link[:host], '', redirects, logger) } # TODO path prefix
    .flatten

  permanent_error_urls = db
    .exec_params(
      'select canonical_url from permanent_errors where start_link_id = $1',
      [start_link_id]
    )
    .map { |row| row["canonical_url"] }

  fetched_urls = (pages.keys + permanent_error_urls).to_set

  initial_seen_urls = (pages.keys + redirects.keys + permanent_error_urls).to_set
  start_links = (pages_links + redirects.values)
    .filter { |link| !fetched_urls.include?(link[:canonical_url]) }
    .uniq { |link| link[:canonical_url] }

  if pages.empty?
    start_links << start_link
  end

  ctx = CrawlContext.new
  http_client = HttpClient.new
  storage = CrawlDbStorage.new(db)

  ctx.seen_urls.merge(initial_seen_urls)
  ctx.fetched_urls.merge(fetched_urls)
  ctx.redirects.merge(redirects)
  crawl_loop(
    start_link_id, start_link[:host], '', start_links, ctx, http_client,
    :no_early_stop, storage, logger
  )
end

class CrawlContext
  def initialize
    @seen_urls = Set.new
    @fetched_urls = Set.new
    @redirects = {}
    @requests_made = 0
    @main_feed_fetched = false
  end

  attr_reader :seen_urls, :fetched_urls, :redirects
  attr_accessor :requests_made, :main_feed_fetched
end

PERMANENT_ERROR_CODES = %w[400 401 402 403 404 405 406 407 410 411 412 413 414 415 416 417 418 451]

def crawl_loop(
  start_link_id, host, path_prefix, start_links, ctx, http_client, early_stop_cond, storage, logger
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
    uri = link[:uri]
    request_start = monotonic_now
    resp = http_client.request(uri, logger)
    request_ms = ((monotonic_now - request_start) * 1000).to_i
    ctx.requests_made += 1

    if resp.code == "200"
      content_type = resp.content_type.split(';')[0]
      is_main_feed = false
      if content_type == "text/html"
        content = resp.body
      elsif !ctx.main_feed_fetched && RSS::Parser.new(resp.body).parse
        content = resp.body
        is_main_feed = true
      else
        content = nil
      end

      page = { fetch_uri: uri, content_type: content_type, content: content }
      ctx.fetched_urls << link[:canonical_url]
      storage.save_page(link[:canonical_url], uri.to_s, content_type, start_link_id, content)
      if is_main_feed
        storage.save_feed(start_link_id, link[:canonical_url])
        ctx.main_feed_fetched = true
      end

      extract_links(page, host, path_prefix, ctx.redirects, logger).each do |new_link|
        next if ctx.seen_urls.include?(new_link[:canonical_url])
        next_queue << new_link
        ctx.seen_urls << new_link[:canonical_url]
        logger.log("Enqueued #{new_link}")
      end
    elsif resp.code.start_with?('3')
      content_type = 'redirect'
      redirection_url = resp.location
      redirection_link = canonicalize_url(redirection_url, logger, uri)

      if link[:uri].to_s == redirection_link[:uri].to_s
        raise "Redirect to the same place, something's wrong"
      end

      if ctx.redirects.key?(link[:canonical_url])
        storage.delete_redirect(link[:canonical_url], start_link_id)
        logger.log("Replacing redirect #{link[:uri]} -> #{redirection_link[:uri]}")
      end

      ctx.redirects[link[:canonical_url]] = redirection_link
      storage.save_redirect(link[:canonical_url], redirection_link[:canonical_url], redirection_link[:uri].to_s, start_link_id)

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
      storage.save_permanent_error(link[:canonical_url], link[:uri], start_link_id, resp.code)
    else
      raise "HTTP #{resp.code}" # TODO more cases here
    end

    if current_queue.empty?
      temp_queue = current_queue
      current_queue = next_queue
      next_queue = temp_queue
      current_depth += 1
    end

    logger.log("total:#{ctx.seen_urls.length} fetched:#{ctx.fetched_urls.length} new:#{ctx.seen_urls.length - initial_seen_urls_count} queued:#{queue1.length + queue2.length} #{resp.code} #{content_type} #{request_ms}ms #{uri}")
  end

  queue1 + queue2
end

def extract_links(page, host, path_prefix, redirects, logger)
  if page[:content_type] != 'text/html'
    return []
  end

  document = Nokogiri::HTML5(page[:content], max_attributes: -1)
  link_elements = document.css('a').to_a + document.css('link').to_a
  links = []
  link_elements.each do |element|
    next unless element.attributes.key?('href')
    url_attribute = element.attributes['href']
    link = canonicalize_url(url_attribute.to_s, logger, page[:fetch_uri])
    next if link.nil? || link[:host] != host || !link[:uri].path.start_with?(path_prefix)
    while redirects.key?(link[:canonical_url]) && link != redirects[link[:canonical_url]]
      link = redirects[link[:canonical_url]]
    end
    link[:type] = element.attributes['type']
    links << link
  end

  links
end

def canonicalize_url(url, logger, fetch_uri = nil)
  begin
    url_stripped = url.strip
    url_newlines_removed = url_stripped.delete("\n")
    if %w[http:// https://].include?(url_newlines_removed)
      return nil
    end
    url_escaped = Addressable::URI.escape(url_newlines_removed)
    uri = URI(url_escaped)
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

  { canonical_url: canonical_url, host: uri.host, uri: uri }
end
