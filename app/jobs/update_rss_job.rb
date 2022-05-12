class UpdateRssJob < ApplicationJob
  queue_as :default

  def perform(subscription_id)
    subscription = Subscription.find_by(id: subscription_id)
    unless subscription
      Rails.logger.info("Subscription not found")
      return
    end

    now = ScheduleHelper.now
    day_of_week = now.day_of_week
    schedule = subscription.schedules.find_by(day_of_week: day_of_week)
    has_published_today = subscription
      .subscription_posts
      .where(
        [
          "date_trunc('day', published_at at time zone 'UTC' at time zone ?) = date_trunc('day', ?::timestamp at time zone 'UTC' at time zone ?)",
          ScheduleHelper::ScheduleDate::PSQL_PACIFIC_TIME_ZONE,
          now.date,
          ScheduleHelper::ScheduleDate::PSQL_PACIFIC_TIME_ZONE
        ]
      )
      .count > 0

    if has_published_today
      Rails.logger.info("Already published posts today, looks like double schedule?")
      return
    end

    if !subscription.is_paused && schedule && schedule.count > 0
      UpdateRssService.update_rss(subscription, schedule.count, now)
    end

    if subscription.subscription_posts.where("published_at is null").length > 0
      UpdateRssJob.schedule_for_tomorrow(subscription_id)
    else
      Rails.logger.info(
        "Subscription #{subscription_id} had its last post published, not rescheduling for tomorrow"
      )
    end
  end
end
