require_relative 'crawling'
require_relative 'db'
require_relative 'logger'

db = db_connect
logger = MyLogger.new($stdout)
# start_crawl(db, 138, logger)
discover_feed(db, 1, logger)
# export_graph(db, 3, logger)
