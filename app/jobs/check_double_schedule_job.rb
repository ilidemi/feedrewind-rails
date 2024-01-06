class CheckDoubleScheduleJob < ApplicationJob
  queue_as :default

  def perform
    # https://stackoverflow.com/a/28668340
    query = <<-SQL
      select array_agg(id) as ids, (
        select regexp_matches(handler, E'arguments:\n  - ([0-9]+)')
      )[1] as user_id
      from delayed_jobs
      where handler like '%PublishPostsJob%'
      group by user_id
      having count(*) > 1
    SQL
    query_result = ActiveRecord::Base.connection.exec_query(query, "SQL", [])

    query_result.rows do |row|
      Rails.logger.warn("User #{row[1]} has duplicated PublishPostsJob: #{row[0]}")
    end

    CheckDoubleScheduleJob.set(wait: 1.hours).perform_later
  end
end
