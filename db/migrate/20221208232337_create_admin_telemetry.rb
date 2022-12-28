class CreateAdminTelemetry < ActiveRecord::Migration[6.1]
  def change
    create_table :admin_telemetries do |t|
      t.text "key", null: false
      t.float "value", null: false
      t.json "extra"

      t.timestamps
    end
  end
end
