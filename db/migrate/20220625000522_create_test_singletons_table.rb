class CreateTestSingletonsTable < ActiveRecord::Migration[6.1]
  def change
    create_table :test_singletons, id: false do |t|
      t.primary_key :key, :text, null: false
      t.column :value, :text

      t.timestamps
    end

    TestSingleton.create!(key: "time_travel_command_id")
    TestSingleton.create!(key: "time_travel_timestamp")
    TestSingleton.create!(key: "email_metadata")
  end
end
