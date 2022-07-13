require 'tzinfo'

class PublishPostsJob < ApplicationJob
  queue_as :default

  def perform(user_id, date_str, scheduled_for_str, is_manual = false)
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
      PublishPostsService.publish_for_user(user_id, utc_now, date, date_str, scheduled_for_str)
    else
      Rails.logger.warn("Today's local date was supposed to be #{date_str} but it's #{local_date_now_str} (#{local_datetime_now}). Skipping today's update.")
    end

    unless is_manual
      next_date = date.next_day
      timezone = TZInfo::Timezone.get(user.user_settings.timezone)
      hour_of_day = PublishPostsJob::get_hour_of_day(user.user_settings.delivery_channel)
      next_run = timezone.local_to_utc(
        DateTime.new(next_date.year, next_date.month, next_date.day, hour_of_day, 0, 0)
      )
      PublishPostsJob
        .set(wait_until: next_run)
        .perform_later(user.id, ScheduleHelper::date_str(next_date), ScheduleHelper::utc_str(next_run))
    end
  end

  def self.initial_schedule(user)
    utc_now = DateTime.now.utc
    date = utc_now.to_date.prev_day
    timezone = TZInfo::Timezone.get(user.user_settings.timezone)
    hour_of_day = PublishPostsJob::get_hour_of_day(user.user_settings.delivery_channel)
    next_run = timezone.local_to_utc(DateTime.new(date.year, date.month, date.day, hour_of_day, 0, 0))
    while next_run < utc_now
      date = date.next_day
      next_run = timezone.local_to_utc(DateTime.new(date.year, date.month, date.day, hour_of_day, 0, 0))
    end

    PublishPostsJob
      .set(wait_until: next_run)
      .perform_later(user.id, ScheduleHelper::date_str(date), ScheduleHelper::utc_str(next_run))
  end

  def self.get_hour_of_day(delivery_channel)
    case delivery_channel
    when "email"
      5
    when "multiple_feeds"
      2
    when "single_feed"
      2
    else
      raise "Unknown delivery channel: #{delivery_channel}"
    end
  end

  LockedJob = Struct.new(:id, :locked_by)

  def self.lock(user_id)
    query = <<-SQL
      select id, locked_by
      from delayed_jobs
      where (handler like concat(E'%class: PublishPostsJob\n%'))
        and handler like concat(E'%arguments:\n  - ', $1::text, E'\n%')
      for update
    SQL
    query_result = ActiveRecord::Base.connection.exec_query(query, "SQL", [user_id])
    query_result.rows.map { |id, locked_by| LockedJob.new(id, locked_by) }
  end

  def self.get_next_scheduled_date(user_id)
    query = <<-SQL
      select (regexp_match(handler, concat(E'arguments:\n  - ', $1::text, E'\n  - ''([0-9-]+)''')))[1]
      from delayed_jobs
      where handler like concat(E'%class: PublishPostsJob\n%') and
        handler like concat(E'%arguments:\n  - ', $1::text, E'\n%')
      order by run_at desc
    SQL
    query_result = ActiveRecord::Base.connection.exec_query(query, "SQL", [user_id])
    return nil if query_result.empty?

    job_date_str = query_result[0]["regexp_match"]
    job_date_str
  end

  def self.update_run_at(job_id, run_at)
    query = <<-SQL
      update delayed_jobs set run_at = $1 where id = $2;
    SQL
    ActiveRecord::Base.connection.exec_query(query, "SQL", [run_at, job_id])
  end

  def self.destroy_user_jobs(user_id)
    query = <<-SQL
      delete from delayed_jobs
      where (handler like concat(E'%class: PublishPostsJob\n%') or
          handler like concat(E'%class: EmailPostsJob\n%') or
          handler like concat(E'%class: EmailInitialItemJob\n%') or
          handler like concat(E'%class: EmailFinalItemJob\n%'))
        and handler like concat(E'%arguments:\n  - ', $1::text, E'\n%')
    SQL
    ActiveRecord::Base.connection.exec_query(query, "SQL", [user_id])
  end

  def self.is_scheduled_for_date(user_id, date_str)
    query = <<-SQL
      select count(*)
      from delayed_jobs
      where handler like concat(E'%class: PublishPostsJob\n%') and
        handler like concat(E'%arguments:\n  - ', $1::text, E'\n  - ', $2::text, '%')
    SQL
    query_result = ActiveRecord::Base.connection.exec_query(query, "SQL", [user_id, date_str])
    query_result.length == 0
  end
end
