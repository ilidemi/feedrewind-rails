task :log_stalled_jobs => :environment do
  hour_ago = DateTime.now.utc.advance(hours: -1)
  query = <<-SQL
      select handler, locked_at from delayed_jobs where locked_at < $1
  SQL
  query_result = ActiveRecord::Base.connection.exec_query(query, "SQL", [hour_ago])
  query_result.rows.each do |row|
    Rails.logger.warn("Stalled job: #{row[0]}")
  end
end
