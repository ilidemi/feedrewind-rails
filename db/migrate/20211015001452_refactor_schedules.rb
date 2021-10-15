class RefactorSchedules < ActiveRecord::Migration[6.1]
  def up
    drop_table :schedules
    create_table :schedules do |t|
      t.references :blog, null: false, foreign_key: true
      t.column :day_of_week, :day_of_week, null: false
      t.integer :count, null: false

      t.timestamps
    end
  end
end
