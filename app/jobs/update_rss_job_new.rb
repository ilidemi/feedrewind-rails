class UpdateRssJobNew < ApplicationJob
  queue_as :default

  def perform(user_id, is_manual = false)
    user = User.find_by(id: user_id)
    unless user
      Rails.logger.info("User not found")
      return
    end

    now = ScheduleHelper.now

    unless is_manual
      query = <<-SQL
      select count(*) from subscriptions
        join (
          select subscription_id, count(*) from subscription_posts
          where date_trunc('day', published_at at time zone 'UTC' at time zone $1) =
            date_trunc('day', $2::timestamp at time zone 'UTC' at time zone $1)
          group by subscription_id
        ) as subscription_posts on subscriptions.id = subscription_posts.subscription_id
        where user_id = $3 and subscription_posts.count > 0
      SQL
      query_result = ActiveRecord::Base.connection.exec_query(
        query, "SQL", [ScheduleHelper::ScheduleDate::PSQL_PACIFIC_TIME_ZONE, now.date, user_id]
      )
      has_published_today = query_result.rows[0][0] > 0

      if has_published_today
        Rails.logger.info("Already published posts today, looks like double schedule?")
        return
      end
    end

    UpdateRssServiceNew.update_for_user(user_id, now)

    unless is_manual
      UpdateRssJobNew.schedule_for_tomorrow(user_id)
    end
  end
end
