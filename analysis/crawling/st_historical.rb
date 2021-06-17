require_relative 'db'
require_relative 'discover_historical_entries'
require_relative 'logger'

db = connect_db
logger = MyLogger.new($stdout)
runnable = HistoricalRunnable.new

start_link_id = 294
result = runnable.run(start_link_id, db, logger)
puts runnable
       .result_column_names
       .zip(result.column_values, result.column_statuses)
       .map { |name, value, status| "#{name}\t#{value}\t#{status}" }
