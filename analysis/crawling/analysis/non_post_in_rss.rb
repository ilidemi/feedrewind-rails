require_relative '../../../app/lib/guided_crawling/canonical_link'
require_relative '../db'
require_relative '../logger'
require_relative '../../../app/lib/guided_crawling/feed_parsing'
require_relative '../../../app/lib/guided_crawling/guided_crawling'

start_link_ids = [209, 150, 145, 147, 217, 225, 251, 301, 304, 324, 338, 370, 375, 410, 439, 440, 458, 230, 132, 140, 409]

db = connect_db
logger = MyLogger.new($stdout)

results = []
start_link_ids.each do |start_link_id|
  row = db.exec_params(
    "select pages.content, pages.fetch_url, historical_ground_truth.pattern from pages "\
    "left join historical_ground_truth on pages.start_link_id = historical_ground_truth.start_link_id "\
    "where pages.id = (select page_id from feeds where start_link_id = $1)",
    [start_link_id]
  ).first
  content = unescape_bytea(row["content"])
  fetch_uri = URI(row["fetch_url"])
  pattern = row["pattern"]
  feed_links = parse_feed(content, fetch_uri, logger)
  feed_uris = feed_links.entry_links.map(&:curi)
  feed_urls = feed_uris.map(&:to_s)
  path_prefix, feed_filtered_curis = try_filter_non_posts_from_feed(feed_uris, Set.new)
  if feed_filtered_curis
    feed_filtered_curis_set = feed_filtered_curis.to_canonical_uri_set(CanonicalEqualityConfig.new(Set.new, false))
    feed_non_post_paths = feed_uris
      .filter { |uri| !feed_filtered_curis_set.include?(uri) }
      .map { |uri| uri.path + uri.query }
    results << {
      urls: feed_urls,
      count: feed_links.entry_links.length,
      removed_count: feed_filtered_curis.length - feed_links.entry_links.length,
      post_prefix: "/" + path_prefix.join("/") + "/*",
      non_post_paths: feed_non_post_paths,
      id: start_link_id,
      pattern: pattern
    }
  else
    results << {
      urls: feed_urls,
      count: feed_links.entry_links.length,
      id: start_link_id,
      pattern: pattern
    }
  end
end

results.sort_by! { |result| result[:count] }

results.each do |result|
  if result.key?(:post_prefix)
    puts "#{result[:id]} #{result[:pattern]} #{result[:count]} #{result[:post_prefix]} #{result[:removed_count]} #{result[:non_post_paths].join(" ")}"
  else
    puts "#{result[:id]} #{result[:pattern]} #{result[:count]}: #{result[:urls]}"
  end
end
