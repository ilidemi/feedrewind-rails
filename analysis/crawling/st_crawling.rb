require_relative 'crawling'
require_relative 'db'
require_relative 'logger'

db = db_connect
logger = MyLogger.new($stdout)
# start_crawl(db, 138, logger)
result = discover_feed(db, 109, logger)
puts CRAWLING_RESULT_COLUMN_NAMES.zip(result.column_values)
# export_graph(db, 3, logger)
