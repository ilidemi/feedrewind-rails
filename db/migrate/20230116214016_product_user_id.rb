class ProductUserId < ActiveRecord::Migration[6.1]
  def change
    ProductEvent.delete_all

    remove_column :product_events, :user_id
    add_column :product_events, :product_user_id, :uuid, null: false
  end
end
