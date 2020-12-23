class AddDayOfWeekToSchedule < ActiveRecord::Migration[6.1]
  def change
    execute <<-SQL
      CREATE TYPE day_of_week AS ENUM('mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun')
    SQL
    add_column :schedules, :day_of_week, :day_of_week
  end
end
