class RemoveDayOfWeekFromSchedule < ActiveRecord::Migration[6.1]
  def change
    remove_column :schedules, :day_of_week, :string
  end
end
