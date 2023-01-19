require 'securerandom'

class SubscriptionPostRandomIds < ActiveRecord::Migration[6.1]
  def change
    add_column :subscription_posts, :random_id, :text

    SubscriptionPost.all.each do |post|
      post.update_attribute(:random_id, SecureRandom.urlsafe_base64(16))
    end

    change_column_null :subscription_posts, :random_id, false
    add_index :subscription_posts, :random_id, unique: true
  end
end
