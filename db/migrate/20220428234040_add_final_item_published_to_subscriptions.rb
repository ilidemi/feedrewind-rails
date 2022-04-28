class AddFinalItemPublishedToSubscriptions < ActiveRecord::Migration[6.1]
  def change
    add_column :subscriptions, :final_item_published_at, :datetime, null: true

    Subscription.with_discarded.each do |subscription|
      next if subscription.subscription_posts.where("published_at is null").count > 0
      next if subscription.subscription_posts.length == 0

      subscription.final_item_published_at = subscription
        .subscription_posts
        .order("published_at desc")
        .limit(1)
        .first
        .published_at

      subscription.save!
    end
  end
end
