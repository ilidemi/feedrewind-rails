require_relative '../db'
require_relative '../logger'
require_relative '../feed_parsing'

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
  feed_links = extract_feed_links(content, fetch_uri, logger)
  results << {
    links: feed_links.entry_links,
    count: feed_links.entry_links.length,
    id: start_link_id,
    pattern: pattern
  }
end

results.sort_by! { |result| result[:count] }

results.each do |result|
  puts "#{result[:id]} #{result[:count]} #{result[:pattern]} #{result[:links].map { |link| link.canonical_uri.to_s }}"
end
