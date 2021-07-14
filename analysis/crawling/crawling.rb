require 'nokogumbo'
require 'set'
require_relative 'canonical_link'
require_relative 'crawling_storage'
require_relative 'feed_parsing'
require_relative 'http_client'
require_relative 'run_common'
require_relative 'structs'

class CrawlContext
  def initialize
    @seen_fetch_urls = Set.new
    @fetched_canonical_uris = CanonicalUriSet.new([], CanonicalEqualityConfig.new(Set.new, false))
    @redirects = {}
    @requests_made = 0
    @duplicate_fetches = 0
    @main_feed_fetched = false
    @allowed_hosts = Set.new
  end

  attr_reader :seen_fetch_urls, :fetched_canonical_uris, :redirects, :allowed_hosts
  attr_accessor :requests_made, :duplicate_fetches, :main_feed_fetched
end

PERMANENT_ERROR_CODES = %w[400 401 402 403 404 405 406 407 410 411 412 413 414 415 416 417 418 451]

AlreadySeenLink = Struct.new(:link)
BadRedirection = Struct.new(:url)

def crawl_request(initial_link, ctx, http_client, is_feed_expected, start_link_id, storage, logger)
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
    if content_type == "text/html" || (is_feed_expected && is_feed(resp.body, logger))
      content = resp.body
    else
      content = nil
    end
    if !ctx.fetched_canonical_uris.include?(link.canonical_uri)
      ctx.fetched_canonical_uris << link.canonical_uri
      storage.save_page(
        link.canonical_uri.to_s, link.url, content_type, start_link_id, content
      )
      logger.log("#{resp.code} #{content_type} #{request_ms}ms #{link.url}")
    else
      logger.log("#{resp.code} #{content_type} #{request_ms}ms #{link.url} - canonical uri already seen but ok")
    end
    Page.new(link.canonical_uri, link.uri, start_link_id, content_type, content)
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
