require 'tzinfo'

class UpdateRssJob < ApplicationJob
  queue_as :default

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
      query_result = ActiveRecord::Base.connection.exec_query(
        query, "SQL", [date_str, user_id]
      )
      has_published_today = query_result.rows[0][0] > 0

      if has_published_today
        Rails.logger.warn("Already published posts today, looks like double schedule?")
        return
      end
    end

    utc_now = DateTime.now.utc
    timezone = TZInfo::Timezone.get(user.user_settings.timezone)
    local_datetime = timezone.utc_to_local(utc_now)
    local_date_str = ScheduleHelper.date_str(local_datetime)
    if local_date_str > date_str
      Rails.logger.warn("Today's local date was supposed to be #{date_str} but it's #{local_date_str} (#{local_datetime}). Skipping till today.")
      date_str = local_date_str
    end
    date = Date.parse(date_str)
    UpdateRssService.update_for_user(user_id, utc_now, date)

    unless is_manual
      UpdateRssJob.schedule_for_2am_tomorrow(user, date)
    end
  end

  def self.get_next_run_time(user, next_date)
    timezone = TZInfo::Timezone.get(user.user_settings.timezone)
    timezone.local_to_utc(DateTime.new(next_date.year, next_date.month, next_date.day, 2, 0, 0))
  end

  def self.initial_schedule(user)
    utc_now = DateTime.now.utc
    date = utc_now.to_date.prev_day
    next_run = UpdateRssJob.get_next_run_time(user, date)
    while next_run < utc_now
      date = date.next_day
      next_run = UpdateRssJob.get_next_run_time(user, date)
    end

    UpdateRssJob.set(wait_until: next_run).perform_later(user.id, date.strftime("%Y-%m-%d"))
  end

  def self.schedule_for_2am_tomorrow(user, current_date)
    next_date = current_date.next_day
    next_run = self.get_next_run_time(user, next_date)
    UpdateRssJob.set(wait_until: next_run).perform_later(user.id, next_date.strftime("%Y-%m-%d"))
  end

  def self.get_next_scheduled_date(user_id)
    query = <<-SQL
      select (regexp_match(handler, concat(E'arguments:\n  - ', $1::text, E'\n  - ''([0-9-]+)''')))[1]
      from delayed_jobs
      where handler like '%class: UpdateRssJob%' and
        handler like concat(E'%arguments:\n  - ', $1::text, '%')
      order by run_at desc
    SQL
    query_result = ActiveRecord::Base.connection.exec_query(query, "SQL", [user_id])
    job_date_str = query_result[0]["regexp_match"]

    utc_now = DateTime.now.utc
    user_settings = UserSettings.find_by(user_id: user_id)
    timezone = TZInfo::Timezone.get(user_settings.timezone)
    local_datetime = timezone.utc_to_local(utc_now)
    local_date_str = ScheduleHelper.date_str(local_datetime)

    if local_date_str > job_date_str
      Rails.logger.warn("Job date was supposed to be #{job_date_str} but today is already #{local_date_str} (#{local_datetime})")
      local_date_str
    else
      job_date_str
    end
  end

  def self.is_scheduled_for_date(user_id, date_str)
    query = <<-SQL
      select count(*)
      from delayed_jobs
      where handler like '%class: UpdateRssJob%' and
        handler like concat(E'%arguments:\n  - ', $1::text, E'\n  - ', $2::text, '%')
    SQL
    query_result = ActiveRecord::Base.connection.exec_query(query, "SQL", [user_id, date_str])
    query_result.length == 0
  end

  def self.lock(user_id)
    query = <<-SQL
      select id, locked_by from delayed_jobs
      where handler like '%UpdateRssJob%'
        and handler like concat(E'%arguments:\n  - ', $1::text, E'\n%')
      for update
    SQL
    query_result = ActiveRecord::Base.connection.exec_query(query, "SQL", [user_id])
    query_result.rows.to_h
  end

  def self.update_run_at(job_id, run_at)
    query = <<-SQL
      update delayed_jobs set run_at = $1 where id = $2;
    SQL
    ActiveRecord::Base.connection.exec_query(query, "SQL", [run_at, job_id])
  end
end
