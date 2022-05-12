class MoveToPerUserRss < ActiveRecord::Migration[6.1]
  def up
    execute "delete from delayed_jobs where handler like '%job_class: UpdateRssJob%'"
    User.all.each do |user|
      UpdateRssJobNew.schedule_for_tomorrow(user.id)
    end
  end

  def down
    execute "delete from delayed_jobs where handler like '%job_class: UpdateRssJobNew%'"
    subscriptions = Subscription
      .where(status: "live")
      .includes(:subscription_posts)
      .to_a
      .filter { |subscription| subscription.subscription_posts.any? { |post| post.published_at.nil? } }
    subscriptions.each do |subscription|
      UpdateRssJob.schedule_for_tomorrow(subscription.id)
    end
  end
end
