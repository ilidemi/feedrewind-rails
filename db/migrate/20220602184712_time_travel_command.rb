class TimeTravelCommand < ActiveRecord::Migration[6.1]
  def change
    create_table :last_time_travels do |t|
      t.bigint :last_command_id, null: true
      t.timestamp :timestamp, null: true
    end

    LastTimeTravel.create!(id: 0, last_command_id: nil, timestamp: nil)
  end
end
