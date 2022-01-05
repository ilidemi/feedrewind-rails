class DeleteLastPostIndexFromSubscriptionPosts < ActiveRecord::Migration[6.1]
  def up
    remove_column :subscriptions, :last_post_index
  end
end
