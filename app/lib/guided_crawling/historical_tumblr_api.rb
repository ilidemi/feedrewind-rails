require 'json'
require_relative 'canonical_link'
require_relative 'historical_common'
require_relative 'util'

def get_tumblr_api_historical(hostname, crawl_ctx, http_client, progress_logger, logger)
  logger.info("Get Tumblr historical start")
  api_key = "REDACTED_TUMBLR_API_KEY"

  links = []
  timestamps = []
  url = "https://api.tumblr.com/v2/blog/#{hostname}/posts?api_key=#{api_key}"
  blog_link = nil
  blog_title = nil
  expected_count = nil
  loop do
    uri = URI(url)
    request_start = monotonic_now
    resp = http_client.request(uri, logger)
    request_ms = ((monotonic_now - request_start) * 1000).to_i
    crawl_ctx.requests_made += 1
    progress_logger.log_html
    logger.info("#{resp.code} #{request_ms}ms #{url}")

    unless resp.code == "200"
      raise "Tumblr error"
    end

    resp_json = JSON.load(resp.body)
    raise "No posts in Tumblr response" unless resp_json["response"] && resp_json["response"]["posts"]

    unless blog_link
      unless resp_json["response"]["blog"] && resp_json["response"]["blog"]["url"]
        raise "No blog url in Tumblr response"
      end
      blog_url = resp_json["response"]["blog"]["url"]
      blog_link = to_canonical_link(blog_url, logger)

      raise "No blog title in Tumblr response" unless resp_json["response"]["blog"]["title"]
      blog_title = resp_json["response"]["blog"]["title"]

      raise "No posts count in Tumblr response" unless resp_json["response"]["blog"]["posts"]
      expected_count = resp_json["response"]["blog"]["posts"]
    end

    resp_json["response"]["posts"].each do |post|
      post_url = post["post_url"]
      post_title = post["title"] || post["summary"]
      normalized_post_title = normalize_title(post_title) || normalize_title(blog_title)
      post_link = to_canonical_link(post_url, logger)
      titled_post_link = link_set_title(post_link, create_link_title(normalized_post_title, :tumblr))
      links << titled_post_link
      timestamps << post["timestamp"]
    end

    requests_remaining = (1.0 * (expected_count - links.length) / 20).ceil
    progress_logger.log_and_save_postprocessing_counts(links.length, requests_remaining)

    if resp_json["response"]["_links"] &&
      resp_json["response"]["_links"]["next"] &&
      resp_json["response"]["_links"]["next"]["href"]

      url = "https://api.tumblr.com" + resp_json["response"]["_links"]["next"]["href"] + "&api_key=#{api_key}"
    else
      break
    end
  end

  are_timestamps_sorted = true
  timestamps.each_cons(2) do |t1, t2|
    are_timestamps_sorted = false unless t1 > t2
  end
  raise "Tumblr posts are not sorted" unless are_timestamps_sorted

  logger.info("Get Tumblr historical finish")
  HistoricalResult.new(
    main_link: blog_link,
    pattern: "tumblr",
    links: links,
    count: links.count,
    extra: ""
  )
end