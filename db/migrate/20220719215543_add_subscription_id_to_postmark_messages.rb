class AddSubscriptionIdToPostmarkMessages < ActiveRecord::Migration[6.1]
  def change
    add_column :postmark_messages, :subscription_id, :bigint, null: false
    add_foreign_key :postmark_messages, :subscriptions
  end
end
