require_relative 'crawling'
require_relative 'db'
require_relative 'logger'

raise "There is a lot of useful stuff in db, pls no wipe"

db = connect_db
logger = MyLogger.new($stdout)
runnable = CrawlRunnable.new

start_link_id = 140
result = runnable.run(start_link_id, db, logger)
puts runnable
       .result_column_names
       .zip(result.column_values, result.column_statuses)
       .map { |name, value, status| "#{name}\t#{value}\t#{status}"}

# export_graph(db, 3, logger)
