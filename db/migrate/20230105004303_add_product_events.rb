class AddProductEvents < ActiveRecord::Migration[6.1]
  def change
    create_table :product_events do |t|
      t.text "user_id", null: false
      t.text "event_type", null: false
      t.json "event_properties"
      t.json "user_properties"
      t.text "user_agent"
      t.text "user_ip"
      t.timestamp "dispatched_at"

      t.timestamps
    end
  end
end
