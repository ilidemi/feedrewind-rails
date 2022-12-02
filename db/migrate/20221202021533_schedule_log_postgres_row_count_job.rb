class ScheduleLogPostgresRowCountJob < ActiveRecord::Migration[6.1]
  def up
    LogPostgresRowCountJob.perform_later
  end

  def down
    execute <<-SQL
      delete from delayed_jobs where handler like '%class: LogPostgresRowCountJob%'
    SQL
  end
end
