require 'net/http'
require 'nokogumbo'
require 'set'
require_relative '../../../app/lib/guided_crawling/canonical_link'
require_relative '../../../app/lib/guided_crawling/feed_parsing'
require_relative '../../../app/lib/guided_crawling/page_parsing'
require_relative '../../../app/lib/guided_crawling/util'

InputRow = Struct.new(:index, :url, :sum_score, :count)

def hn_rss(input_rows, throttler, logger)
  out_feeds = []
  out_scores = []
  out_redirects = []
  out_rows_processed = []
  out_errors = []

  input_rows.each do |input_row|
    index, url, sum_score, count = input_row.to_a
    logger.info("[[#{index}]] Url #{url}, sum_score #{sum_score}, count #{count}")

    prefix_urls_curls = get_prefix_urls_curls(url)
    begin
      uri = URI(url)
      http_host = uri.host
      http_port = uri.port
      Net::HTTP.start(
        http_host,
        http_port,
        read_timeout: 10,
        open_timeout: 10,
        use_ssl: uri.scheme == "https"
      ) do |http|
        feed_found = false
        prefix_urls_curls.each do |prefix_url_curl|
          logger.info("Trying prefix #{prefix_url_curl.url}")
          prefix_uri = URI(prefix_url_curl.url)
          throttler.throttle(prefix_uri.host)
          seen_urls = [prefix_uri.to_s]

          loop do
            req = Net::HTTP::Get.new(prefix_uri, initheader = { 'User-Agent' => 'Feeduler/0.1' })
            if prefix_uri.host == http_host && prefix_uri.port == http_port
              resp = http.request(req)
            else
              resp = Net::HTTP.start(
                prefix_uri.host,
                prefix_uri.port,
                read_timeout: 10,
                open_timeout: 10,
                use_ssl: prefix_uri.scheme == "https"
              ) do |http2|
                http2.request(req)
              end
            end

            if resp.code.start_with?('3')
              redirection_link = to_canonical_link(resp.header["location"], logger, prefix_uri)
              if redirection_link.nil?
                logger.info("#{resp.code} #{prefix_url_curl.url} -> bad redirection link")
                break
              end

              if seen_urls.include?(redirection_link.url)
                logger.info("#{resp.code} #{prefix_url_curl.url} -> #{redirection_link.url} - infinite redirect")
                break
              end
              seen_urls << redirection_link.url

              logger.info("#{resp.code} #{prefix_url_curl.url} -> #{redirection_link.url}")
              prefix_uri = redirection_link.uri
              next
            elsif resp.code == "200"
              logger.info("#{resp.code} #{prefix_url_curl.url}")

              content_type = resp.header["content-type"]&.split(";")&.first
              unless content_type == "text/html"
                logger.info("Not an html")
                break
              end

              page_doc = nokogiri_html5(resp.body)
              feed_links = find_feed_links(
                page_doc, prefix_uri, throttler, http, http_host, http_port, logger
              )
              if feed_links.empty?
                logger.info("No feed links")
                break
              end

              # out_redirects << [prefix_url_curl.curl, prefix_uri.to_s]

              feed_links.each do |feed_link|
                logger.info("Feed found: #{prefix_uri.to_s} -> #{feed_link.url}")
                out_feeds << [prefix_uri.to_s, feed_link.url]
                out_scores << [prefix_uri.to_s, sum_score, count]
              end

              feed_found = true
              break
            else
              logger.info("#{resp.code} #{prefix_url_curl.url} - some error")
              break
            end
          end

          break if feed_found
        end

        out_rows_processed << index
      end
    rescue => e
      logger.info(e)
      out_errors << index
    end
  end

  [out_feeds, out_scores, out_redirects, out_rows_processed, out_errors]
end

class Throttler
  def initialize
    @last_request_by_host = Hash.new(0)
  end

  def throttle(host)
    now = monotonic_now
    if now - @last_request_by_host[host] < 1.0
      sleep(1.0 - (now - @last_request_by_host[host]))
    end
    @last_request_by_host[host] = monotonic_now
  end
end

UrlCurl = Struct.new(:url, :curl)

def get_prefix_urls_curls(url)
  prefix_urls_curls = []
  prefix_url = url
  while prefix_url.count('/') >= 2
    prefix_curl = prefix_url.sub(/^https?:\/\//, '')
    prefix_urls_curls << UrlCurl.new(prefix_url, prefix_curl)
    prefix_url = prefix_url.rpartition("/").first
  end

  prefix_urls_curls
end

def find_feed_links(page_doc, page_uri, throttler, http, http_host, http_port, logger)
  probable_feed_links = page_doc
    .xpath("/html/head/link[@rel='alternate']")
    .to_a
    .filter { |link| %w[application/rss+xml application/atom+xml].include?(link.attributes["type"]&.value) }
    .map { |link| link.attributes["href"]&.value }
    .map { |url| to_canonical_link(url, logger, page_uri) }
    .filter { |link| link }
    .filter { |link| !link.url.end_with?("?alt=rss") }
    .filter { |link| !link.url.end_with?("/comments/feed/") }
    .filter { |link| !link.url.end_with?("/comments/feed") }

  page_links = extract_links(page_doc, page_uri, nil, nil, logger)
  page_feed_links = page_links.filter do |page_link|
    page_link &&
      (page_link.uri.host == "feeds.feedburner.com" ||
        page_link.curi.trimmed_path&.match?(/\/[^\/]+\.(?:xml|rss|atom)$/) ||
        page_link.curi.trimmed_path&.match?(/\/(?:feed|rss|atom)$/) ||
        page_link.curi.trimmed_path&.match?(/\/(?:feeds?|rss|atom)\//))
  end

  probable_feed_links.push(*page_feed_links)
  probable_feed_links.uniq! { |feed_link| feed_link.url }

  if probable_feed_links.length > 10
    logger.info("Too many probable feeds (#{probable_feed_links.length}")
    return []
  end

  logger.info("Checking #{probable_feed_links.length} probable feeds")
  feed_links = probable_feed_links.filter do |feed_link|
    begin
      throttler.throttle(feed_link.uri.host)
      content = nil
      seen_urls = [feed_link.url]
      loop do
        req = Net::HTTP::Get.new(feed_link.uri, initheader = { 'User-Agent' => 'Feeduler/0.1' })
        if feed_link.uri.host == http_host && feed_link.uri.port == http_port
          resp = http.request(req)
        else
          resp = Net::HTTP.start(
            feed_link.uri.host,
            feed_link.uri.port,
            read_timeout: 10,
            open_timeout: 10,
            use_ssl: feed_link.uri.scheme == "https"
          ) do |http2|
            http2.request(req)
          end
        end

        if resp.code.start_with?('3')
          redirection_link = to_canonical_link(resp.header["location"], logger, feed_link.uri)
          if redirection_link.nil?
            logger.info("Feed #{resp.code} #{feed_link.url} -> bad redirection link")
            break
          end

          if seen_urls.include?(redirection_link.url)
            logger.info("Feed #{resp.code} #{feed_link.url} -> #{redirection_link.url} - infinite redirect")
            break
          end
          seen_urls << redirection_link.url

          logger.info("#{resp.code} #{feed_link.url} -> #{redirection_link.url}")
          feed_link = redirection_link
          next
        elsif resp.code == "200"
          content = resp.body
          break
        else
          logger.info("Feed not 200: #{resp.code} #{feed_link.url} (#{page_uri})")
          break
        end
      end
      next unless content

      is_feed = is_feed(content, logger)
      logger.info("Is#{is_feed ? "" : " not"} feed: #{feed_link.url}")
      is_feed
    rescue => e
      logger.info(e)
      next
    end
  end

  feed_links
end