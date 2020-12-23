class CreateSchedules < ActiveRecord::Migration[6.1]
  def change
    create_table :schedules do |t|
      t.references :blog, null: false, foreign_key: true
      t.string :day_of_week

      t.timestamps
    end
  end
end
