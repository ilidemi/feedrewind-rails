require "json"

class AdminTestController < ApplicationController
  def travel_31days
    TimeTravelHelper::travel_to(DateTime.now.utc.advance(days: 31))
    render plain: "#{now_pdt}"
  end

  def travel_back
    TimeTravelHelper::travel_back
    render plain: "#{now_pdt}"
  end

  def travel_to_v2
    timestamp = DateTime.parse(params[:timestamp])

    TimeTravelHelper::travel_to(timestamp)

    command_id = RandomId::generate_random_bigint
    epoch =  Time.at(0).utc.to_datetime
    TimeTravelJob
      .set(wait_until: epoch)
      .perform_later(command_id, "travel_to", timestamp)
    compare_timestamps(command_id)

    render plain: DateTime.now.utc.iso8601
  end

  def travel_back_v2
    TimeTravelHelper::travel_back

    command_id = RandomId::generate_random_bigint
    epoch =  Time.at(0).utc.to_datetime
    TimeTravelJob
      .set(wait_until: epoch)
      .perform_later(command_id, "travel_back", nil)
    compare_timestamps(command_id)

    render plain: DateTime.now.utc.iso8601
  end

  def wait_for_update_rss_job
    fill_current_user

    utc_now = DateTime.now.utc
    timezone = TZInfo::Timezone.get(@current_user.user_settings.timezone)
    local_datetime = timezone.utc_to_local(utc_now)
    local_date_str = ScheduleHelper::date_str(local_datetime)

    poll_count = 0
    while true
      is_scheduled_for_date = UpdateRssJob::is_scheduled_for_date(@current_user.id, local_date_str)
      break unless is_scheduled_for_date

      sleep(0.1)
      poll_count += 1
      raise "Job didn't run" if poll_count >= 10
    end

    render plain: "OK"
  end

  def destroy_user_subscriptions
    fill_current_user
    @current_user.destroy_subscriptions_recursively!
    render plain: "OK"
  end

  def reschedule_update_rss_job
    fill_current_user

    query = <<-SQL
      delete from delayed_jobs
      where handler like '%class: UpdateRssJob%' and handler like concat('%', $1::text, '%')
    SQL
    ActiveRecord::Base.connection.exec_query(query, "SQL", [@current_user.id])

    UpdateRssJob.initial_schedule(@current_user)
    render plain: "OK"
  end

  def run_reset_failed_blogs_job
    ResetFailedBlogsJob.new.perform(false)
    render plain: "OK"
  end

  def destroy_user
    user = User.find_by(email: params[:email])
    return render plain: "NotFound" unless user

    user.destroy_subscriptions_recursively!
    user.destroy!
    render plain: "OK"
  end

  def user_timezone
    user = User.find_by(email: params[:email])
    render plain: user.user_settings.timezone
  end

  def execute_sql
    query_result = ActiveRecord::Base.connection.exec_query(params[:query], "SQL", [])
    render plain: JSON.dump(query_result.to_a)
  end

  private

  def now_pdt
    DateTime.now.in_time_zone('Pacific Time (US & Canada)')
  end

  def compare_timestamps(command_id)
    last_time_travel = nil
    LastTimeTravel.uncached do
      poll_count = 0
      while true
        last_time_travel = LastTimeTravel.find(0)
        #noinspection RubyResolve
        break if last_time_travel.last_command_id == command_id

        sleep(0.1)
        poll_count += 1
        raise "Worker didn't time travel (command #{command_id})" if poll_count >= 30
      end
    end

    web_timestamp = DateTime.now.utc
    #noinspection RubyNilAnalysis
    difference = (last_time_travel.timestamp - web_timestamp).abs
    if difference > 60
      raise "Web timestamp #{web_timestamp} doesn't match worker timestamp #{last_time_travel.timestamp}"
    end
  end
end
