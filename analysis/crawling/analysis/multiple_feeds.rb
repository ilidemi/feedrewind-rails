require_relative '../db'
require_relative '../logger'
require_relative '../mock_logger'
require_relative '../../../app/lib/guided_crawling/crawling'
require_relative '../../../app/lib/guided_crawling/feed_discovery'
require_relative '../../../app/lib/guided_crawling/http_client'

if ARGV.length != 2
  partition_count = 1
  partition_number = 1
else
  partition_count = ARGV[0].to_i
  partition_number = ARGV[1].to_i
end

multiple_feeds_ids = %w[21 54 83 106 109 123 130 153 194 199 203 241 380 436 445 491 494 533 543 544 545 546 581 612]

db = connect_db
logger = MyLogger.new(STDOUT)
ids_urls = db.exec(
  "select start_links.id, start_links.url from start_links "\
  "inner join guided_successes on start_link_id = start_links.id "\
  "where start_links.url is not null "\
  "and start_links.id in (#{multiple_feeds_ids.join(", ")}) "\
  "order by id asc"
).map { |row| [row["id"].to_i, row["url"]] }

logger.info("#{ids_urls.length} rows")

partition_size = (ids_urls.length / partition_count).ceil.to_i
partition_start = (partition_number - 1) * partition_size
partition = ids_urls.slice(partition_start, partition_size)
logger.info("Partition #{partition_start}..#{partition_start + partition.length - 1}")

crawl_ctx = CrawlContext.new
http_client = HttpClient.new(false)
mock_logger = MockLogger.new

partition.each do |id, url|
  begin
    discover_result = discover_feeds_at_url(url, nil, crawl_ctx, http_client, mock_logger)
    next unless discover_result.is_a?(DiscoveredMultipleFeeds)

    logger.info("#{id} #{discover_result.class} feeds:#{discover_result.start_feeds.length}")
    discover_result.start_feeds.each do |feed|
      logger.info("#{feed.title} #{feed.final_url}")
    end
  rescue => err
    logger.info("error #{err}")
  end

end