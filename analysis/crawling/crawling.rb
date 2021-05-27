require 'addressable/uri'
require 'net/http'
require 'nokogumbo'
require 'set'
require_relative 'db'
require_relative 'logger'

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
    .map { |_, page| extract_links(page, start_link[:host], redirects, logger) }
    .flatten

  notfounds = db
    .exec_params(
      'select canonical_url from notfounds where start_link_id = $1',
      [start_link_id]
    )
    .map { |row| row["canonical_url"] }

  fetched_links = (pages.keys + notfounds).to_set

  initial_seen_links = (pages.keys + redirects.keys + notfounds).to_set
  start_links = (pages_links + redirects.values)
    .filter { |link| !fetched_links.include?(link[:canonical_url]) }
    .uniq { |link| link[:canonical_url] }

  if pages.empty?
    start_links << start_link
  end

  crawl_loop(db, start_link_id, start_link[:host], initial_seen_links, start_links, fetched_links, redirects, logger)
end

def crawl_loop(db, start_link_id, host, initial_seen_links, start_links, fetched_links, redirects, logger)
  links_queue = []
  seen_links = Set.new
  start_links.each do |link|
    links_queue << link
    seen_links << link[:canonical_url]
    logger.log("Enqueued #{link}")
  end

  initial_seen_links.each do |canonical_url|
    seen_links << canonical_url
  end

  prev_timestamp = nil

  until links_queue.empty?
    if seen_links.length >= 3600
      raise "That's a lot of links. Is the blog really this big?"
    end

    link = links_queue.shift
    logger.log("Dequeued #{link}")
    uri = link[:uri]
    request = Net::HTTP::Get.new(uri)
    prev_timestamp = throttle(prev_timestamp)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
      http.request(request)
    end

    if response.code == "200"
      content_type = response.header["content-type"].split(';')[0]
      if %w[text/html application/xml].include?(content_type)
        content = response.body
      else
        content = nil
      end
      page = { fetch_uri: uri, content_type: content_type, content: content }
      fetched_links << link[:canonical_url]
      db.exec_params(
        'insert into pages (canonical_url, fetch_url, content_type, start_link_id, content) values ($1, $2, $3, $4, $5)',
        [link[:canonical_url], uri.to_s, content_type, start_link_id, content]
      )

      extract_links(page, host, redirects, logger).each do |new_link|
        next if seen_links.include?(new_link[:canonical_url])
        links_queue << new_link
        seen_links << new_link[:canonical_url]
        logger.log("Enqueued #{new_link}")
      end
    elsif %w[301 302].include?(response.code)
      content_type = 'redirect'
      redirection_url = response.header["location"]
      redirection_link = canonicalize_url(redirection_url, logger, uri)
      if redirects.key?(link[:canonical_url])
        db.exec_params(
          'delete from redirects where from_canonical_url = $1 and start_link_id = $2',
          [link[:canonical_url], start_link_id]
        )
        logger.log("Replacing redirect #{link[:uri]} -> #{redirection_link[:uri]}")
      end

      redirects[link[:canonical_url]] = redirection_link
      db.exec_params(
        'insert into redirects (from_canonical_url, to_canonical_url, to_fetch_url, start_link_id) values ($1, $2, $3, $4)',
        [link[:canonical_url], redirection_link[:canonical_url], redirection_link[:uri].to_s, start_link_id]
      )

      is_new_redirection = !seen_links.include?(redirection_link[:canonical_url])
      is_redirection_not_fetched = link[:canonical_url] == redirection_link[:canonical_url] &&
        !fetched_links.include?(link[:canonical_url])

      if is_new_redirection || is_redirection_not_fetched
        links_queue << redirection_link
        seen_links << redirection_link[:canonical_url]
        logger.log("Enqueued #{redirection_link}")
      end
    elsif response.code == "404"
      content_type = 'notfound'
      fetched_links << link[:canonical_url]
      db.exec_params(
        'insert into notfounds (canonical_url, start_link_id) values ($1, $2)',
        [link[:canonical_url], start_link_id]
      )
    else
      response.value # TODO more cases here
    end

    logger.log("total:#{seen_links.length} fetched:#{fetched_links.length} new:#{seen_links.length - initial_seen_links.length} queue:#{links_queue.length} #{response.code} #{content_type} #{uri}")
  end
end

def throttle(prev_timestamp)
  new_timestamp = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  unless prev_timestamp.nil?
    time_delta = new_timestamp - prev_timestamp
    if time_delta < 1.0
      sleep(1.0 - time_delta)
      new_timestamp = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
  new_timestamp
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
    link = canonicalize_url(url_attribute.to_s, logger, page[:fetch_uri])
    next if link.nil? || link[:host] != host
    while redirects.key?(link[:canonical_url]) && link != redirects[link[:canonical_url]]
      link = redirects[link[:canonical_url]]
    end
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

  port_str = (
    uri.port.nil? || (uri.port == 80 && uri.scheme == 'http') || (uri.port == 443 && uri.scheme == 'https')
  ) ? '' : ":#{uri.port}"
  path_str = (uri.path == '/' && uri.query.nil?) ? '' : uri.path
  query_str = uri.query.nil? ? '' : "?#{uri.query}"
  canonical_url = "#{uri.host}#{port_str}#{path_str}#{query_str}" # drop scheme and fragment
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

db = db_connect
logger = MyLogger.new($stdout)
start_crawl(db, 136, logger)
