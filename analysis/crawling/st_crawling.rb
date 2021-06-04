require_relative 'crawling'
require_relative 'db'
require_relative 'logger'

db = db_connect
logger = MyLogger.new($stdout)

result = discover_feed(db, 11, logger)
puts CrawlingResult.column_names.zip(result.column_values, result.column_statuses)

# export_graph(db, 3, logger)
