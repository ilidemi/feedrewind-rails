class DropTimeTravel < ActiveRecord::Migration[6.1]
  def change
    drop_table :last_time_travels
  end
end
