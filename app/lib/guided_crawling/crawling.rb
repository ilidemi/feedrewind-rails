require_relative 'http_client'
require_relative 'page_parsing'
require_relative 'puppeteer_client'
require_relative 'structs'
require_relative 'util'

class CrawlContext
  def initialize
    @seen_fetch_urls = Set.new
    @fetched_curis = CanonicalUriSet.new([], CanonicalEqualityConfig.new(Set.new, false))
    @pptr_fetched_curis = CanonicalUriSet.new([], CanonicalEqualityConfig.new(Set.new, false))
    @redirects = {}
    @requests_made = 0
    @puppeteer_requests_made = 0
    @duplicate_fetches = 0
    @title_requests_made = 0
  end

  attr_reader :seen_fetch_urls, :fetched_curis, :pptr_fetched_curis, :redirects
  attr_accessor :requests_made, :puppeteer_requests_made, :duplicate_fetches, :title_requests_made
end

PERMANENT_ERROR_CODES = %w[400 401 402 403 404 405 406 407 410 411 412 413 414 415 416 417 418 451]

AlreadySeenLink = Struct.new(:link)
BadRedirection = Struct.new(:url)

def crawl_request(initial_link, is_feed_expected, crawl_ctx, http_client, progress_logger, logger)
  link = initial_link
  seen_urls = [link.url]
  link = follow_cached_redirects(link, crawl_ctx.redirects, seen_urls)
  if !link.equal?(initial_link) &&
    (crawl_ctx.seen_fetch_urls.include?(link.url) ||
      crawl_ctx.fetched_curis.include?(link.curi))

    logger.info("Cached redirect #{initial_link.url} -> #{link.url} (already seen)")
    return AlreadySeenLink.new(link)
  end

  http_errors_count = 0

  loop do
    request_start = monotonic_now
    resp = http_client.request(link.uri, logger)
    request_ms = ((monotonic_now - request_start) * 1000).to_i
    crawl_ctx.requests_made += 1
    progress_logger.log_html

    if resp.code.start_with?('3')
      redirection_url = resp.location
      redirection_link_or_result = process_redirect(
        redirection_url, initial_link, link, resp.code, request_ms, seen_urls, crawl_ctx, logger
      )

      if redirection_link_or_result.is_a?(Link)
        link = redirection_link_or_result
      else
        return redirection_link_or_result
      end
    elsif resp.code == "200"
      if resp.content_type
        content_type_tokens = resp
          .content_type
          .split(';')
          .map(&:strip)
        content_type = content_type_tokens.first
        charset_token = content_type_tokens
          .find { |token| token.downcase.start_with?('charset') }
        if charset_token
          encoding = charset_token.split("=").last.strip
        else
          encoding = "utf-8"
        end
        body = resp.body.force_encoding(encoding)
      else
        content_type = nil
        body = resp.body.force_encoding("utf-8")
      end

      if content_type == "text/html"
        content = body
        document = nokogiri_html5(content)
      elsif is_feed_expected && is_feed(body, logger)
        content = body
        document = nil
      else
        content = nil
        document = nil
      end

      meta_refresh_content = document&.at_xpath("/html/head/meta[@http-equiv='refresh']/@content")&.value
      if meta_refresh_content
        meta_refresh_match = meta_refresh_content.match(/(\d+); *(?:URL|url)=(.+)/)
        if meta_refresh_match
          interval_str = meta_refresh_match[1]
          redirection_url = meta_refresh_match[2]
          log_code = "#{resp.code}_meta_refresh_#{interval_str}"

          redirection_link_or_result = process_redirect(
            redirection_url, initial_link, link, log_code, request_ms, seen_urls, crawl_ctx, logger
          )

          if redirection_link_or_result.is_a?(Link)
            link = redirection_link_or_result
            next
          else
            return redirection_link_or_result
          end
        end
      end

      if !crawl_ctx.fetched_curis.include?(link.curi)
        crawl_ctx.fetched_curis << link.curi
        logger.info("#{resp.code} #{content_type} #{request_ms}ms #{link.url}")
      else
        logger.info("#{resp.code} #{content_type} #{request_ms}ms #{link.url} - canonical uri already seen")
      end

      return Page.new(link.curi, link.uri, content, document)
    elsif resp.code == "SSLError"
      if link.uri.host.start_with?("www.")
        new_uri = link.uri.clone
        new_uri.host.gsub!(/^www\./, "")
        new_url = new_uri.to_s
        logger.info("SSLError_www #{request_ms}ms #{link.url} -> #{new_url}")
        link = to_canonical_link(new_url, logger)
        next
      else
        logger.info("SSLError #{request_ms}ms #{link.url}")
        raise "SSLError"
      end
    elsif PERMANENT_ERROR_CODES.include?(resp.code) || http_errors_count >= 3
      crawl_ctx.fetched_curis << link.curi
      logger.info("#{resp.code} #{request_ms}ms #{link.url} - permanent error")
      return PermanentError.new(link.curi, link.url, resp.code)
    elsif http_errors_count < 3
      sleep_interval = http_client.get_retry_delay(http_errors_count)
      logger.info("#{resp.code} #{request_ms}ms #{link.url} - sleeping #{sleep_interval}s")
      sleep(sleep_interval)
      http_errors_count += 1
      next
    else
      raise "Unexpected crawling branch"
    end
  end
end

def process_redirect(
  redirection_url, initial_link, request_link, code, request_ms, seen_urls, crawl_ctx, logger
)
  redirection_link = to_canonical_link(redirection_url, logger, request_link.uri)

  if redirection_link.nil?
    logger.info("#{code} #{request_ms}ms #{request_link.url} -> bad redirection link")
    return BadRedirection.new(redirection_url)
  end

  if seen_urls.include?(redirection_link.url)
    raise "Circular redirect for #{initial_link.url}: #{seen_urls} -> #{redirection_link.url}"
  end
  seen_urls << redirection_link.url
  crawl_ctx.redirects[request_link.url] = redirection_link
  redirection_link = follow_cached_redirects(redirection_link, crawl_ctx.redirects, seen_urls)

  if crawl_ctx.seen_fetch_urls.include?(redirection_link.url) ||
    crawl_ctx.fetched_curis.include?(redirection_link.curi)

    logger.info("#{code} #{request_ms}ms #{request_link.url} -> #{redirection_link.url} (already seen)")
    return AlreadySeenLink.new(request_link)
  end

  logger.info("#{code} #{request_ms}ms #{request_link.url} -> #{redirection_link.url}")
  # Not marking canonical url as seen because redirect key is a fetch url which may be different for the
  # same canonical url
  crawl_ctx.seen_fetch_urls << redirection_link.url
  redirection_link
end

LOAD_MORE_SELECTOR = "a[class*=load-more], button[class*=load-more]"
MEDIUM_FEED_LINK_SELECTOR = "link[rel=alternate][type='application/rss+xml'][href^='https://medium.']"
SUBSTACK_FOOTER_SELECTOR = "[class*=footer-substack]"
BUTTONDOWN_TWITTER_XPATH = "/html/head/meta[@name='twitter:site'][@content='@buttondown']"

def is_load_more(page)
  page.document.at_css(LOAD_MORE_SELECTOR)
end

def is_medium_list(page)
  page.document.at_css(MEDIUM_FEED_LINK_SELECTOR) &&
    page.document.css("button").any? { |button| button.text.downcase == "show more" }
end

def is_substack_archive(page)
  page.curi.trimmed_path&.match?("/archive/*$") &&
    page.document.at_css(SUBSTACK_FOOTER_SELECTOR)
end

def is_buttondown(page)
  page.document.at_xpath(BUTTONDOWN_TWITTER_XPATH)
end

def is_puppeteer_match(page)
  return false unless page.document

  is_load_more(page) ||
    is_medium_list(page) ||
    is_substack_archive(page) ||
    is_buttondown(page)
end

def crawl_with_puppeteer_if_match(page, match_curis_set, puppeteer_client, crawl_ctx, progress_logger, logger)
  return page unless puppeteer_client && page.document

  pptr_content = nil
  if is_load_more(page)
    logger.info("Found load more button, rerunning with puppeteer")
    pptr_content = puppeteer_client.fetch(
      page.fetch_uri, match_curis_set, crawl_ctx, progress_logger, logger
    ) do |pptr_page|
      pptr_page.query_visible_selector(LOAD_MORE_SELECTOR)
    end
  elsif is_medium_list(page)
    logger.info("Spotted Medium page, rerunning with puppeteer")
    pptr_content = puppeteer_client.fetch(
      page.fetch_uri, match_curis_set, crawl_ctx, progress_logger, logger
    ) do |pptr_page|
      pptr_page
        .query_selector_all("button")
        .filter { |button| button.evaluate("b => b.textContent").downcase == "show more" }
        .first
    end
  elsif is_substack_archive(page)
    logger.info("Spotted Substack archives, rerunning with puppeteer")
    pptr_content = puppeteer_client.fetch(page.fetch_uri, match_curis_set, crawl_ctx, progress_logger, logger)
  elsif is_buttondown(page)
    logger.info("Spotted Buttondown page, rerunning with puppeteer")
    pptr_content = puppeteer_client.fetch(page.fetch_uri, match_curis_set, crawl_ctx, progress_logger, logger)
  end

  return page unless pptr_content

  if !crawl_ctx.pptr_fetched_curis.include?(page.curi)
    crawl_ctx.pptr_fetched_curis << page.curi
    logger.info("Puppeteer page saved")
  else
    logger.info("Puppeteer page saved - canonical uri already seen")
  end

  pptr_document = nokogiri_html5(pptr_content)
  Page.new(page.curi, page.fetch_uri, pptr_content, pptr_document)
end