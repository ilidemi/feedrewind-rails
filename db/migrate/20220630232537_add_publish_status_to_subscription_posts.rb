class AddPublishStatusToSubscriptionPosts < ActiveRecord::Migration[6.1]
  def change
    reversible do |dir|
      dir.up { execute "create type post_publish_status as enum('rss_published', 'email_pending', 'email_skipped')" }
      dir.down { execute "drop type post_publish_status" }
    end

    add_column :subscription_posts, :publish_status, "post_publish_status"
  end
end
