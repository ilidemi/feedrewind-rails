module UserJobHelper
  def self.initial_daily_schedule(job_class, user, hour_of_day)
    utc_now = DateTime.now.utc
    date = utc_now.to_date.prev_day
    timezone = TZInfo::Timezone.get(user.user_settings.timezone)
    next_run = self.get_next_run_time(date, timezone, hour_of_day)
    while next_run < utc_now
      date = date.next_day
      next_run = self.get_next_run_time(date, timezone, hour_of_day)
    end

    job_class
      .set(wait_until: next_run)
      .perform_later(user.id, ScheduleHelper::date_str(date))
  end

  def self.schedule_for_tomorrow(job_class, user, current_date, hour_of_day)
    next_date = current_date.next_day
    timezone = TZInfo::Timezone.get(user.user_settings.timezone)
    next_run = self.get_next_run_time(next_date, timezone, hour_of_day)
    job_class
      .set(wait_until: next_run)
      .perform_later(user.id, ScheduleHelper::date_str(next_date))
  end

  LockedJob = Struct.new(:type, :id, :locked_by)

  def self.lock_daily_jobs(user_id)
    query = <<-SQL
      select (regexp_match(handler, E'class: ([a-zA-Z]+)\n'))[1] as job_type, id, locked_by
      from delayed_jobs
      where (handler like concat(E'%class: UpdateRssJob\n%') or
          handler like concat(E'%class: EmailPostsJob\n%'))
        and handler like concat(E'%arguments:\n  - ', $1::text, E'\n%')
      for update
    SQL
    query_result = ActiveRecord::Base.connection.exec_query(query, "SQL", [user_id])
    query_result.rows.map { |job_type, id, locked_by| LockedJob.new(job_type, id, locked_by) }
  end

  def self.get_next_scheduled_date(job_class, user_id)
    query = <<-SQL
      select (regexp_match(handler, concat(E'arguments:\n  - ', $1::text, E'\n  - ''([0-9-]+)''')))[1]
      from delayed_jobs
      where handler like concat(E'%class: ', $2::text, '\n%') and
        handler like concat(E'%arguments:\n  - ', $1::text, E'\n%')
      order by run_at desc
    SQL
    query_result = ActiveRecord::Base.connection.exec_query(query, "SQL", [user_id, job_class.to_s])
    job_date_str = query_result[0]["regexp_match"]
    job_date_str
  end

  def self.update_run_at(job_id, run_at)
    query = <<-SQL
      update delayed_jobs set run_at = $1 where id = $2;
    SQL
    ActiveRecord::Base.connection.exec_query(query, "SQL", [run_at, job_id])
  end

  def self.destroy_job(job_id)
    query = <<-SQL
      delete from delayed_jobs where id = $1
    SQL
    ActiveRecord::Base.connection.exec_query(query, "SQL", [job_id])
  end

  def self.is_scheduled_for_date(job_class, user_id, date_str)
    query = <<-SQL
      select count(*)
      from delayed_jobs
      where handler like concat(E'%class: ', $1::text, '\n%') and
        handler like concat(E'%arguments:\n  - ', $2::text, E'\n  - ', $3::text, '%')
    SQL
    query_result = ActiveRecord::Base.connection.exec_query(query, "SQL", [job_class.to_s, user_id, date_str])
    query_result.length == 0
  end

  def self.destroy_daily_jobs(user_id)
    query = <<-SQL
      delete from delayed_jobs
      where (handler like concat(E'%class: UpdateRssJob\n%') or
          handler like concat(E'%class: EmailPostsJob\n%'))
        and handler like concat(E'%arguments:\n  - ', $1::text, E'\n%')
    SQL
    ActiveRecord::Base.connection.exec_query(query, "SQL", [user_id])
  end

  private

  def self.get_next_run_time(next_date, timezone, hour_of_day)
    timezone.local_to_utc(DateTime.new(next_date.year, next_date.month, next_date.day, hour_of_day, 0, 0))
  end
end
