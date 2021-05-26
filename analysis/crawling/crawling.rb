require 'net/http'
require 'nokogumbo'
require 'set'

def start_crawl(db, start_link_id, log_file)
  start_link_url = db.exec_params('select url from start_links where id = $1', [start_link_id])[0]["url"]
  start_link = canonicalize_url(start_link_url)

  pages = db
    .exec_params(
      'select canonical_url, fetch_url, content_type, content from pages where start_link_id = $1', [start_link_id]
    )
    .map { |row| [row["canonical_url"], { fetch_uri: URI(row["fetch_url"]), content_type: row["content_type"], content: row["content"] }] }
    .to_h

  pages_links = pages
    .map { |_, page| extract_links(page, start_link[:host]) }
    .flatten
  pages_new_links = pages_links.filter { |link| !pages.key?(link[:canonical_url]) }

  start_links = pages_new_links.clone
  if pages.empty?
    start_links << start_link
  end

  crawl_loop(db, start_link_id, start_link[:host], pages, start_links, log_file)
end

def crawl_loop(db, start_link_id, host, pages, start_links, log_file)
  links_queue = Queue.new
  seen_links = Set.new
  start_links.each do |link|
    links_queue << link
    seen_links << link[:canonical_url]
  end

  pages.each_key do |canonical_url|
    seen_links << canonical_url
  end

  prev_timestamp = nil
  new_pages_count = 0

  until links_queue.empty?
    link = links_queue.deq
    uri = link[:uri]
    request = Net::HTTP::Get.new(uri)
    prev_timestamp = throttle(prev_timestamp)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
      http.request(request)
    end
    response.value # TODO more cases here

    content_type = response.header["content-type"].split(';')[0]
    if %w[text/html application/xml].include?(content_type)
      content = response.body
    else
      content = nil
    end
    page = { fetch_uri: uri, content_type: content_type, content: content }
    pages[link[:canonical_url]] = page
    db.exec_params(
      'insert into pages (canonical_url, fetch_url, content_type, start_link_id, content) values ($1, $2, $3, $4, $5)',
      [link[:canonical_url], uri.to_s, content_type, start_link_id, content]
    )
    new_pages_count += 1

    extract_links(page, host).each do |new_link|
      next if seen_links.include?(new_link[:canonical_url])
      links_queue << new_link
      seen_links << new_link[:canonical_url]
    end

    log_file.write("#{Time.new} #{pages.length} #{new_pages_count} #{links_queue.length} #{content_type} #{uri}\n")
    log_file.flush
  end
end

def throttle(prev_timestamp)
  new_timestamp = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  unless prev_timestamp.nil?
    time_delta = new_timestamp - prev_timestamp
    if time_delta < 1.0
      sleep(1.0 - time_delta)
    end
  end
  new_timestamp
end

def extract_links(page, host)
  if page[:content_type] != 'text/html'
    return []
  end

  document = Nokogiri::HTML5(page[:content])
  link_elements = document.css('a').to_a + document.css('link').to_a
  links = []
  link_elements.each do |element|
    url = element.attributes['href']
    link = canonicalize_url(url, page[:fetch_uri])
    next if link.nil? || link[:host] != host
    links << link
  end

  links
end

def canonicalize_url(url, fetch_uri = nil)
  uri = URI(url)

  if uri.scheme.nil? && uri.host.nil? && !fetch_uri.nil? # Relative uri
    fetch_uri_classes = { 'http' => URI::HTTP, 'https' => URI::HTTPS }
    uri = fetch_uri_classes[fetch_uri.scheme].build(host: fetch_uri.host, path: uri.path, query: uri.query)
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
  if uri.userinfo != nil || uri.registry != nil || uri.opaque != nil
    raise "URI has extra parts: #{uri}"
  end
  { canonical_url: canonical_url, host: uri.host, uri: uri }
end
