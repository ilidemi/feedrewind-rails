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
    @main_feed_fetched = false
    @allowed_hosts = Set.new
  end

  attr_reader :seen_fetch_urls, :fetched_curis, :pptr_fetched_curis, :redirects, :allowed_hosts
  attr_accessor :requests_made, :puppeteer_requests_made, :duplicate_fetches, :main_feed_fetched
end

PERMANENT_ERROR_CODES = %w[400 401 402 403 404 405 406 407 410 411 412 413 414 415 416 417 418 451]

AlreadySeenLink = Struct.new(:link)
BadRedirection = Struct.new(:url)

def crawl_request(
  initial_link, crawl_ctx, http_client, puppeteer_client, is_feed_expected, start_link_id, db_storage, logger
)
  link = initial_link
  seen_urls = [link.url]
  link = follow_cached_redirects(link, crawl_ctx.redirects, seen_urls)
  if !link.equal?(initial_link) &&
    (crawl_ctx.seen_fetch_urls.include?(link.url) ||
      crawl_ctx.fetched_curis.include?(link.curi))

    logger.log("Cached redirect #{initial_link.url} -> #{link.url} (already seen)")
    return AlreadySeenLink.new(link)
  end

  http_errors_count = 0

  loop do
    request_start = monotonic_now
    resp = http_client.request(link.uri, logger)
    request_ms = ((monotonic_now - request_start) * 1000).to_i
    crawl_ctx.requests_made += 1

    if resp.code.start_with?('3')
      redirection_url = resp.location
      redirection_link_or_result = process_redirect(
        redirection_url, initial_link, link, resp.code, request_ms, seen_urls, start_link_id, crawl_ctx,
        db_storage, logger
      )

      if redirection_link_or_result.is_a?(Link)
        link = redirection_link_or_result
      else
        return redirection_link_or_result
      end
    elsif resp.code == "200"
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

      meta_refresh_content = document&.at_xpath("/html/head/meta[@http-equiv='refresh']/@content")&.value
      if meta_refresh_content
        meta_refresh_match = meta_refresh_content.match(/(\d+); *(?:URL|url)=(.+)/)
        if meta_refresh_match
          interval_str = meta_refresh_match[1]
          redirection_url = meta_refresh_match[2]
          log_code = "#{resp.code}_meta_refresh_#{interval_str}"

          redirection_link_or_result = process_redirect(
            redirection_url, initial_link, link, log_code, request_ms, seen_urls, start_link_id, crawl_ctx,
            db_storage, logger
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
        db_storage.save_page(
          link.curi.to_s, link.url, content_type, start_link_id, content, false
        )
        logger.log("#{resp.code} #{content_type} #{request_ms}ms #{link.url}")
      else
        logger.log("#{resp.code} #{content_type} #{request_ms}ms #{link.url} - canonical uri already seen")
      end

      # TODO: puppeteer will be executed twice for duplicate fetches
      content, document, is_puppeteer_used = crawl_link_with_puppeteer(
        link, content, document, puppeteer_client, crawl_ctx, logger
      )
      if is_puppeteer_used
        if !crawl_ctx.pptr_fetched_curis.include?(link.curi)
          crawl_ctx.pptr_fetched_curis << link.curi
          db_storage.save_page(
            link.curi.to_s, link.url, content_type, start_link_id, content, true
          )
          logger.log("Puppeteer page saved")
        else
          logger.log("Puppeteer page saved - canonical uri already seen")
        end
      end

      return Page.new(link.curi, link.uri, start_link_id, content_type, content, document, is_puppeteer_used)
    elsif resp.code == "SSLError"
      if link.uri.host.start_with?("www.")
        new_uri = link.uri.clone
        new_uri.host.gsub!(/^www\./, "")
        new_url = new_uri.to_s
        logger.log("SSLError_www #{request_ms}ms #{link.url} -> #{new_url}")
        link = to_canonical_link(new_url, logger)
        next
      else
        logger.log("SSLError #{request_ms}ms #{link.url}")
        raise "SSLError"
      end
    elsif PERMANENT_ERROR_CODES.include?(resp.code) || http_errors_count >= 3
      crawl_ctx.fetched_curis << link.curi
      db_storage.save_permanent_error(link.curi.to_s, link.url, start_link_id, resp.code)
      logger.log("#{resp.code} #{request_ms}ms #{link.url} - permanent error")
      return PermanentError.new(link.curi, link.url, start_link_id, resp.code)
    elsif http_errors_count < 3
      sleep_interval = http_client.get_retry_delay(http_errors_count)
      logger.log("#{resp.code} #{request_ms}ms #{link.url} - sleeping #{sleep_interval}s")
      sleep(sleep_interval)
      http_errors_count += 1
      next
    else
      raise "Unexpected crawling branch"
    end
  end
end

def process_redirect(
  redirection_url, initial_link, request_link, code, request_ms, seen_urls, start_link_id, crawl_ctx,
  db_storage, logger
)
  redirection_link = to_canonical_link(redirection_url, logger, request_link.uri)

  if redirection_link.nil?
    logger.log("#{code} #{request_ms}ms #{request_link.url} -> bad redirection link")
    return BadRedirection.new(redirection_url)
  end

  if seen_urls.include?(redirection_link.url)
    raise "Circular redirect for #{initial_link.url}: #{seen_urls} -> #{redirection_link.url}"
  end
  seen_urls << redirection_link.url
  crawl_ctx.redirects[request_link.url] = redirection_link
  db_storage.save_redirect(request_link.url, redirection_link.url, start_link_id)
  redirection_link = follow_cached_redirects(redirection_link, crawl_ctx.redirects, seen_urls)

  if crawl_ctx.seen_fetch_urls.include?(redirection_link.url) ||
    crawl_ctx.fetched_curis.include?(redirection_link.curi)

    logger.log("#{code} #{request_ms}ms #{request_link.url} -> #{redirection_link.url} (already seen)")
    return AlreadySeenLink.new(request_link)
  end

  logger.log("#{code} #{request_ms}ms #{request_link.url} -> #{redirection_link.url}")
  # Not marking canonical url as seen because redirect key is a fetch url which may be different for the
  # same canonical url
  crawl_ctx.seen_fetch_urls << redirection_link.url
  crawl_ctx.allowed_hosts << redirection_link.uri.host
  redirection_link
end
