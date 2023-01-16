class SubscriptionAnonProductUserId < ActiveRecord::Migration[6.1]
  def change
    add_column :subscriptions, :anon_product_user_id, :uuid
  end
end
