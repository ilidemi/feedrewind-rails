class DummyProductUserIds < ActiveRecord::Migration[6.1]
  def up
    rename_column :product_events, :product_user_id, :product_user_uuid
    add_column :product_events, :product_user_id, :text
    ProductEvent.all.each do |product_event|
      product_event.product_user_id = product_event.product_user_uuid.to_s
      product_event.save!
    end
    remove_column :product_events, :product_user_uuid
    change_column_null :product_events, :product_user_id, false
  end
end
