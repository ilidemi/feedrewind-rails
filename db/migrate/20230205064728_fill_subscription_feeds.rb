class FillSubscriptionFeeds < ActiveRecord::Migration[6.1]
  def change
    Subscription.all.each do |sub|
      next if SubscriptionRss.exists?(subscription_id: sub.id)

      PublishPostsService.create_empty_subscription_feed(sub)
    end
  end
end
