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

class PuppeteerClient
  def fetch(uri, match_curis_set, crawl_ctx, progress_logger, logger, &find_load_more_button)
    logger.info("Puppeteer start: #{uri}")
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
          pptr_page.goto(uri.to_s, wait_until: "networkidle0")
          progress_logger.log_and_save_puppeteer

          if match_curis_set
            initial_content = pptr_page.content
            initial_document = nokogiri_html5(initial_content)
            initial_links = extract_links(initial_document, uri, nil, nil, logger, false, false)
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
                progress_logger.log_and_save_puppeteer
                load_more_button = find_load_more_button.call(pptr_page)
              end
            else
              logger.info("Scrolling")
              pptr_page.wait_and_scroll(logger)
              progress_logger.log_and_save_puppeteer
            end
            content = pptr_page.content
          else
            logger.info("Puppeteer didn't find any matching links on initial load")
            #noinspection RubyScope
            content = initial_content
          end

          pptr_page.close
          crawl_ctx.puppeteer_requests_made += pptr_page.finished_requests
          logger.info("Puppeteer done (#{monotonic_now - puppeteer_start}s, #{pptr_page.finished_requests} req)")

          return content
        end
      rescue Puppeteer::FrameManager::NavigationError
        timeout_errors_count += 1
        logger.info("Recovered Puppeteer timeout (#{timeout_errors_count})")
        raise if timeout_errors_count >= 3
      end
    end
  end
end