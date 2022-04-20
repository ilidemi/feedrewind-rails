class RemoveIsPublishedFromSubscriptionPosts < ActiveRecord::Migration[6.1]
  def change
    remove_column :subscription_posts, :is_published
  end
end
