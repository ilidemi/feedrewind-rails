require 'puppeteer'
require_relative 'db'
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
      logger.log("Got exception while clicking")
      logger.log("Page content:")
      logger.log(content)
      raise
    end

    while (monotonic_now - start_time) < 1.0 || # always wait for 1 second
      ((@ongoing_requests > 0 || (monotonic_now - @last_event_time) < 1.0) && # wait if a request is in flight and 1 second after it's finished
        (monotonic_now - @last_event_time) < 10.0) do
      # but time out if something is stuck in flight for 10 seconds

      logger.log("Wait and scroll - finished: #{@finished_requests} ongoing: #{@ongoing_requests} time: #{monotonic_now - start_time}")
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

def crawl_link_with_puppeteer(link, content, document, puppeteer_client, ctx, logger)
  is_puppeteer_used = false
  if puppeteer_client && document
    if document.at_css(LOAD_MORE_SELECTOR)
      logger.log("Found load more button, rerunning with puppeteer")
      content, document = puppeteer_client.fetch(link.url, ctx, logger) do |pptr_page|
        pptr_page.query_visible_selector(LOAD_MORE_SELECTOR)
      end
      is_puppeteer_used = true
    elsif document.at_css(MEDIUM_FEED_LINK_SELECTOR) &&
      document.css("button").any? { |button| button.text.downcase == "show more" }

      logger.log("Spotted Medium page, rerunning with puppeteer")
      content, document = puppeteer_client.fetch(link.url, ctx, logger) do |pptr_page|
        pptr_page
          .query_selector_all("button")
          .filter { |button| button.evaluate("b => b.textContent").downcase == "show more" }
          .first
      end
      is_puppeteer_used = true
    elsif link.curi.path.match?(ARCHIVES_REGEX) &&
      document.at_css(SUBSTACK_FOOTER_SELECTOR)

      logger.log("Spotted Substack archives, rerunning with puppeteer")
      content, document = puppeteer_client.fetch(link.url, ctx, logger)
      is_puppeteer_used = true
    elsif document.at_xpath(BUTTONDOWN_TWITTER_XPATH)
      logger.log("Spotted Buttondown page, rerunning with puppeteer")
      content, document = puppeteer_client.fetch(link.url, ctx, logger)
      is_puppeteer_used = true
    end
  end

  [content, document, is_puppeteer_used]
end

class PuppeteerClient
  def fetch(url, ctx, logger, &find_load_more_button)
    puppeteer_start = monotonic_now
    Puppeteer.launch do |browser|
      pptr_page = browser.new_page
      pptr_page.request_interception = true
      pptr_page.on("request") do |request|
        %w[image font].include?(request.resource_type) ? request.abort : request.continue
      end
      pptr_page.enable_request_tracking
      pptr_page.goto(url, wait_until: "networkidle0")
      if find_load_more_button
        load_more_button = find_load_more_button.call(pptr_page)
        while load_more_button do
          logger.log("Clicking load more button")
          pptr_page.wait_and_scroll(logger) { load_more_button.click }
          load_more_button = find_load_more_button.call(pptr_page)
        end
      else
        logger.log("Scrolling")
        pptr_page.wait_and_scroll(logger)
      end
      content = pptr_page.content
      document = nokogiri_html5(content)
      pptr_page.close
      ctx.puppeteer_requests_made += pptr_page.finished_requests
      logger.log("Puppeteer done (#{monotonic_now - puppeteer_start}s, #{pptr_page.finished_requests} req)")
      return [content, document]
    end
  end
end

class MockPuppeteerClient
  def initialize(db, start_link_id)
    @db = db
    @start_link_id = start_link_id
  end

  def fetch(url, _, _)
    row = @db.exec_params(
      "select content from mock_pages where start_link_id = $1 and fetch_url = $2 and is_from_puppeteer",
      [@start_link_id, url]
    ).first

    if row
      content = unescape_bytea(row["content"])
      document = nokogiri_html5(content)
      return [content, document]
    end
    raise "Couldn't find puppeteer mock page: #{url}"
  end
end