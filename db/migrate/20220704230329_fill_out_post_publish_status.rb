class FillOutPostPublishStatus < ActiveRecord::Migration[6.1]
  def change
    SubscriptionPost
      .where("published_at is not null")
      .each do |subscription_post|
      subscription_post.update_attribute("publish_status", "rss_published")
    end

    Subscription
      .with_discarded
      .where("finished_setup_at is not null")
      .each do |subscription|
      subscription.initial_item_publish_status = "rss_published"
      subscription.save!
    end

    Subscription
      .with_discarded
      .where("final_item_published_at is not null")
      .each do |subscription|
      subscription.final_item_publish_status = "rss_published"
      subscription.save!
    end
  end
end
