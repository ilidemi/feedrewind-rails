require 'tzinfo'

class UpdateRssJob < ApplicationJob
  queue_as :default

  HOUR_OF_DAY = 2

  def perform(user_id, date_str, is_manual = false)
    user = User.find_by(id: user_id)
    unless user
      Rails.logger.info("User not found")
      return
    end

    unless is_manual
      query = <<-SQL
      select count(*) from subscriptions
        join (
          select subscription_id, count(*) from subscription_posts
          where published_at_local_date = $1
          group by subscription_id
        ) as subscription_posts on subscriptions.id = subscription_posts.subscription_id
        where user_id = $2 and subscription_posts.count > 0 and discarded_at is null
      SQL
      query_result = ActiveRecord::Base.connection.exec_query(query, "SQL", [date_str, user_id])
      has_published_today = query_result.rows[0][0] > 0

      if has_published_today
        Rails.logger.warn("Already published posts today, looks like double schedule? Breaking the cycle.")
        return
      end
    end

    date = Date.parse(date_str)
    utc_now = DateTime.now.utc
    timezone = TZInfo::Timezone.get(user.user_settings.timezone)
    local_datetime_now = timezone.utc_to_local(utc_now)
    local_date_now_str = ScheduleHelper.date_str(local_datetime_now)
    if date_str >= local_date_now_str
      UpdateRssService.update_for_user(user_id, utc_now, date)
    else
      Rails.logger.warn("Today's local date was supposed to be #{date_str} but it's #{local_date_now_str} (#{local_datetime_now}). Skipping today's update.")
    end

    unless is_manual
      UserJobHelper::schedule_for_tomorrow(UpdateRssJob, user, date, HOUR_OF_DAY)
    end
  end

  def self.initial_schedule(user)
    UserJobHelper::initial_daily_schedule(UpdateRssJob, user, HOUR_OF_DAY)
  end
end
