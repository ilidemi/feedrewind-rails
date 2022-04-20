class UpdateRssJob < ApplicationJob
  queue_as :default

  def perform(subscription_id)
    subscription = Subscription.find_by(id: subscription_id)
    return unless subscription

    day_of_week = ScheduleHelper.now.day_of_week
    schedule = subscription.schedules.find_by(day_of_week: day_of_week)
    if !subscription.is_paused && schedule && schedule.count > 0
      UpdateRssService.update_rss(subscription, schedule.count)
    end

    if subscription.subscription_posts.where("published_at is null").length > 0
      UpdateRssJob.schedule_for_tomorrow(subscription_id)
    end
  end
end
