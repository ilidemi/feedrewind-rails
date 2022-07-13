class AddPublishStatusToSubscription < ActiveRecord::Migration[6.1]
  def change
    add_column :subscriptions, :initial_item_publish_status, "post_publish_status"
    add_column :subscriptions, :final_item_publish_status, "post_publish_status"

    Subscription.with_discarded.each do |subscription|
      if subscription.finished_setup_at != nil
        subscription.initial_item_publish_status = "rss_published"
        subscription.save!
      end

      if subscription.final_item_published_at != nil
        subscription.final_item_publish_status = "rss_published"
        subscription.save!
      end
    end
  end
end
