require_relative 'db'
require_relative 'logger'

def st_run(runnable, start_link_id)
  db = connect_db
  logger = MyLogger.new($stdout)
  error = nil
  begin
    result = runnable.run(start_link_id, false, db, logger)
  rescue RunError => e
    result = e.result
    error = e
  end
  puts runnable
         .result_column_names
         .zip(result.column_values, result.column_statuses)
         .map { |name, value, status| "#{name}\t#{value}\t#{status}" }
  if error
    raise error, error.cause
  end
end


