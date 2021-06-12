require_relative 'crawling'
require_relative 'db'
require_relative 'logger'

db = connect_db
logger = MyLogger.new($stdout)

start_link_id = 470
result = crawl(db, start_link_id, logger)
puts CrawlingResult
       .column_names
       .zip(result.column_values, result.column_statuses)
       .map { |name, value, status| "#{name}\t#{value}\t#{status}"}

# export_graph(db, 3, logger)
