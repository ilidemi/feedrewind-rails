require 'puppeteer'
require_relative 'util'

class Puppeteer::Page
  def enable_request_tracking
    @last_event_time = monotonic_now
    @ongoing_requests = 0
    @finished_requests = 0
    add_event_listener('request') do |_|
      @last_event_time = monotonic_now
      @ongoing_requests += 1
    end
    add_event_listener('requestfailed') do |_|
      @last_event_time = monotonic_now
      @ongoing_requests -= 1
    end
    add_event_listener('requestfinished') do |_|
      @last_event_time = monotonic_now
      @ongoing_requests -= 1
      @finished_requests += 1
    end
  end

  def wait_and_scroll(logger)
    start_time = monotonic_now

    begin
      yield if block_given?
    rescue
      logger.info("Got exception while clicking")
      logger.info("Page content:")
      logger.info(content)
      raise
    end

    loop do
      now = monotonic_now
      break if (now - start_time) >= 30.0

      under_second_passed = (now - start_time) < 1.0
      request_recently_in_flight = @ongoing_requests > 0 || (monotonic_now - @last_event_time) < 1.0
      request_stuck_in_flight = (monotonic_now - @last_event_time) >= 10.0
      break unless under_second_passed || (request_recently_in_flight && !request_stuck_in_flight)

      logger.info("Wait and scroll - finished: #{@finished_requests} ongoing: #{@ongoing_requests} time: #{now - start_time}")
      evaluate("window.scrollBy(0, document.body.scrollHeight);")
      sleep(0.1)
    end
  end

  def query_visible_selector(selector)
    element = query_selector(selector)
    element if element&.bounding_box
  end

  attr_reader :finished_requests
end

LOAD_MORE_SELECTOR = "a[class*=load-more], button[class*=load-more]"
MEDIUM_FEED_LINK_SELECTOR = "link[rel=alternate][type='application/rss+xml'][href^='https://medium.']"
SUBSTACK_FOOTER_SELECTOR = "[class*=footer-substack]"
BUTTONDOWN_TWITTER_XPATH = "/html/head/meta[@name='twitter:site'][@content='@buttondown']"

def crawl_link_with_puppeteer(
  link, content, document, match_curis_set, puppeteer_client, crawl_ctx, logger
)
  is_puppeteer_used = false
  if puppeteer_client && document
    if document.at_css(LOAD_MORE_SELECTOR)
      logger.info("Found load more button, rerunning with puppeteer")
      content, document = puppeteer_client.fetch(link, match_curis_set, crawl_ctx, logger) do |pptr_page|
        pptr_page.query_visible_selector(LOAD_MORE_SELECTOR)
      end
      is_puppeteer_used = true
    elsif document.at_css(MEDIUM_FEED_LINK_SELECTOR) &&
      document.css("button").any? { |button| button.text.downcase == "show more" }

      logger.info("Spotted Medium page, rerunning with puppeteer")
      content, document = puppeteer_client.fetch(link, match_curis_set, crawl_ctx, logger) do |pptr_page|
        pptr_page
          .query_selector_all("button")
          .filter { |button| button.evaluate("b => b.textContent").downcase == "show more" }
          .first
      end
      is_puppeteer_used = true
    elsif link.curi.trimmed_path&.match?("/archive/*$") &&
      document.at_css(SUBSTACK_FOOTER_SELECTOR)

      logger.info("Spotted Substack archives, rerunning with puppeteer")
      content, document = puppeteer_client.fetch(link, match_curis_set, crawl_ctx, logger)
      is_puppeteer_used = true
    elsif document.at_xpath(BUTTONDOWN_TWITTER_XPATH)
      logger.info("Spotted Buttondown page, rerunning with puppeteer")
      content, document = puppeteer_client.fetch(link, match_curis_set, crawl_ctx, logger)
      is_puppeteer_used = true
    end
  end

  [content, document, is_puppeteer_used]
end

class PuppeteerClient
  def fetch(link, match_curis_set, crawl_ctx, logger, &find_load_more_button)
    logger.info("Puppeteer start: #{link.url}")
    puppeteer_start = monotonic_now

    timeout_errors_count = 0
    loop do
      begin
        Puppeteer.launch do |browser|
          pptr_page = browser.new_page
          pptr_page.request_interception = true
          pptr_page.on("request") do |request|
            %w[image font].include?(request.resource_type) ? request.abort : request.continue
          end
          pptr_page.enable_request_tracking
          pptr_page.goto(link.url, wait_until: "networkidle0")

          if match_curis_set
            initial_content = pptr_page.content
            initial_document = nokogiri_html5(initial_content)
            initial_links = extract_links(initial_document, link.uri, nil, nil, logger, false, false)
            is_scrolling_allowed = initial_links.any? { |page_link| match_curis_set.include?(page_link.curi) }
          else
            is_scrolling_allowed = true
          end

          if is_scrolling_allowed
            if find_load_more_button
              load_more_button = find_load_more_button.call(pptr_page)
              while load_more_button do
                logger.info("Clicking load more button")
                pptr_page.wait_and_scroll(logger) { load_more_button.click }
                load_more_button = find_load_more_button.call(pptr_page)
              end
            else
              logger.info("Scrolling")
              pptr_page.wait_and_scroll(logger)
            end
            content = pptr_page.content
            document = nokogiri_html5(content)
          else
            logger.info("Puppeteer didn't find any matching links on initial load")
            #noinspection RubyScope
            content = initial_content
            #noinspection RubyScope
            document = initial_document
          end

          pptr_page.close
          crawl_ctx.puppeteer_requests_made += pptr_page.finished_requests
          logger.info("Puppeteer done (#{monotonic_now - puppeteer_start}s, #{pptr_page.finished_requests} req)")

          return [content, document]
        end
      rescue Puppeteer::FrameManager::NavigationError
        timeout_errors_count += 1
        logger.info("Recovered Puppeteer timeout (#{timeout_errors_count})")
        raise if timeout_errors_count >= 3
      end
    end
  end
end