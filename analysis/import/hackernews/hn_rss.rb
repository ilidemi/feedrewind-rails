require 'csv'
require 'net/http'
require 'nokogumbo'
require 'set'
require 'sqlite3'
require_relative '../../crawling/canonical_link'
require_relative '../../crawling/logger'
require_relative '../../crawling/feed_parsing'
require_relative '../../crawling/page_parsing'
require_relative '../../crawling/util'

cutoff = 1000

logger = MyLogger.new($stdout)

urls_csv = CSV.read('up_submissions.csv')[1..]
cutoff_index = urls_csv.index { |_, sum_score, _| sum_score.to_i < cutoff }
if cutoff_index
  top_urls_csv = urls_csv[...cutoff_index]
else
  top_urls_csv = urls_csv
end
logger.log("#{urls_csv.length} rows total, #{top_urls_csv.length} over cutoff of #{cutoff}")

db = SQLite3::Database.new("hn.db")

curls_fetched = db
  .execute("select curl from curls_fetched")
  .map(&:first)
  .to_set

urls_with_feed = db
  .execute("select url from feeds")
  .map(&:first)
  .to_set

redirects = db
  .execute("select prefix_curl, url from redirects")
  .to_h

indices_processed = db
  .execute("select row from rows_processed")
  .map(&:first)
  .map(&:to_i)
  .to_set

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
    .filter { |link| !link.url.end_with?("?alt=rss") }
    .filter { |link| !link.url.end_with?("/comments/feed/") }
    .filter { |link| !link.url.end_with?("/comments/feed") }

  page_links = extract_links(page_doc, page_uri, nil, nil, logger)
  page_feed_links = page_links.filter do |page_link|
    page_link.uri.host == "feeds.feedburner.com" ||
      page_link.curi.trimmed_path&.match?(/\/[^\/]+\.(?:xml|rss|atom)$/) ||
      page_link.curi.trimmed_path&.match?(/\/(?:feed|rss|atom)$/) ||
      page_link.curi.trimmed_path&.match?(/\/(?:feeds?|rss|atom)\//)
  end

  probable_feed_links.push(*page_feed_links)
  probable_feed_links.uniq! { |feed_link| feed_link.url }

  logger.log("Checking #{probable_feed_links.length} probable feeds")
  feed_links = probable_feed_links.filter do |feed_link|
    begin
      throttler.throttle(feed_link.uri.host)
      content = nil
      seen_urls = [feed_link.url]
      loop do
        req = Net::HTTP::Get.new(feed_link.uri, initheader = { 'User-Agent' => 'rss-catchup/0.1' })
        if feed_link.uri.host == http_host && feed_link.uri.port == http_port
          resp = http.request(req)
        else
          http2_host = feed_link.uri.host
          http2_port = feed_link.uri.port
          resp = Net::HTTP.start(http2_host, http2_port, use_ssl: feed_link.uri.scheme == "https") do |http2|
            http2.request(req)
          end
        end

        if resp.code.start_with?('3')
          redirection_link = to_canonical_link(resp.header["location"], logger, feed_link.uri)
          if redirection_link.nil?
            logger.log("Feed #{resp.code} #{feed_link.url} -> bad redirection link")
            break
          end

          if seen_urls.include?(redirection_link.url)
            logger.log("Feed #{resp.code} #{feed_link.url} -> #{redirection_link.url} - infinite redirect")
            break
          end
          seen_urls << redirection_link.url

          logger.log("#{resp.code} #{feed_link.url} -> #{redirection_link.url}")
          feed_link = redirection_link
          next
        elsif resp.code == "200"
          content = resp.body
          break
        else
          logger.log("Feed not 200: #{resp.code} #{feed_link.url} (#{page_uri})")
          break
        end
      end
      next unless content

      is_feed = is_feed(content, logger)
      logger.log("Is#{is_feed ? "" : " not"} feed: #{feed_link.url}")
      is_feed
    rescue => e
      logger.log(e)
      next
    end
  end

  feed_links
end

throttler = Throttler.new
url_index = 0
top_urls_csv.each do |url, sum_score, count|
  url_index += 1
  logger.log("#{url_index}/#{top_urls_csv.length} Url #{url}, sum_score #{sum_score}, count #{count}")
  if indices_processed.include?(url_index)
    logger.log("Url already processed")
    next
  end

  prefix_urls_curls = get_prefix_urls_curls(url)
  feed_urls = prefix_urls_curls.filter_map do |prefix_url_curl|
    url = redirects[prefix_url_curl.curl] || prefix_url_curl.url
    url if urls_with_feed.include?(url)
  end
  feed_url = feed_urls.first

  if feed_url
    logger.log("Feed already known for this url, bumping score")
    db.execute(
      "insert into scores (url, sum_score, count) values (?, ?, ?)",
      [feed_url, sum_score.to_i, count.to_i]
    )
    next
  end

  if prefix_urls_curls.all? { |prefix_url_curl| curls_fetched.include?(prefix_url_curl.curl) }
    logger.log("Url already fetched")
    next
  end

  begin
    uri = URI(url)
    http_host = uri.host
    http_port = uri.port
    Net::HTTP.start(http_host, http_port, use_ssl: uri.scheme == "https") do |http|
      feed_found = false
      prefix_urls_curls.each do |prefix_url_curl|
        logger.log("Trying prefix #{prefix_url_curl.url}")
        prefix_uri = URI(prefix_url_curl.url)
        throttler.throttle(prefix_uri.host)
        seen_urls = [prefix_uri.to_s]

        loop do
          req = Net::HTTP::Get.new(prefix_uri, initheader = { 'User-Agent' => 'rss-catchup/0.1' })
          if prefix_uri.host == http_host && prefix_uri.port == http_port
            resp = http.request(req)
          else
            http2_host = prefix_uri.host
            http2_port = prefix_uri.port
            resp = Net::HTTP.start(http2_host, http2_port, use_ssl: prefix_uri.scheme == "https") do |http2|
              http2.request(req)
            end
          end

          if resp.code.start_with?('3')
            redirection_link = to_canonical_link(resp.header["location"], logger, prefix_uri)
            if redirection_link.nil?
              logger.log("#{resp.code} #{prefix_url_curl.url} -> bad redirection link")
              break
            end

            if seen_urls.include?(redirection_link.url)
              logger.log("#{resp.code} #{prefix_url_curl.url} -> #{redirection_link.url} - infinite redirect")
              break
            end
            seen_urls << redirection_link.url

            logger.log("#{resp.code} #{prefix_url_curl.url} -> #{redirection_link.url}")
            prefix_uri = redirection_link.uri
            next
          elsif resp.code == "200"
            logger.log("#{resp.code} #{prefix_url_curl.url}")
            redirects[prefix_url_curl.curl] = prefix_uri.to_s
            db.execute(
              "insert into redirects (prefix_curl, url) values (?, ?)",
              [prefix_url_curl.curl, prefix_uri.to_s]
            )

            content_type = resp.header["content-type"]&.split(";")&.first
            unless content_type == "text/html"
              logger.log("Not an html")
              break
            end

            page_doc = nokogiri_html5(resp.body)
            feed_links = find_feed_links(page_doc, prefix_uri, throttler, http, http_host, http_port, logger)
            if feed_links.empty?
              logger.log("No feed links")
              break
            end

            feed_links.each do |feed_link|
              logger.log("Feed found: #{prefix_uri.to_s} -> #{feed_link.url}")
              urls_with_feed << prefix_uri.to_s
              db.execute(
                "insert into feeds (url, feed_url) values (?, ?)",
                [prefix_uri.to_s, feed_link.url]
              )
              db.execute(
                "insert into scores (url, sum_score, count) values (?, ?, ?)",
                [prefix_uri.to_s, sum_score.to_i, count.to_i]
              )
            end

            feed_found = true
            break
          else
            logger.log("#{resp.code} #{prefix_url_curl.url} - some error")
            break
          end
        end

        curls_fetched << prefix_url_curl.curl
        db.execute("insert into curls_fetched (curl) values (?)", [prefix_url_curl.curl])
        db.execute("insert into rows_processed (row) values (?)", [url_index])

        break if feed_found
      end
    end
  rescue => e
    logger.log(e)
  end
end

# How to parallelize?
# Each domain goes to one process only, so that overlaps are processed sequentially
# Need to throttle within domain, no need to throttle across. Just do sufficiently many processes I guess?
# Disk io is much faster than all these requests so have the main process collect the results and write them
# Process just returns [feeds, scores, fetched]
# So preload the files in each process but then keep in memory filters per process, because don't want to
# continue syncing this data across all processes
# I wonder how long would it take to get all 200k