require "json"
require "postmark"

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
    epoch = Time.at(0).utc.to_datetime
    TimeTravelJob
      .set(wait_until: epoch)
      .perform_later(command_id, "travel_to", timestamp)
    compare_timestamps(command_id)

    render plain: DateTime.now.utc.iso8601
  end

  def travel_back_v2
    TimeTravelHelper::travel_back

    command_id = RandomId::generate_random_bigint
    epoch = Time.at(0).utc.to_datetime
    TimeTravelJob
      .set(wait_until: epoch)
      .perform_later(command_id, "travel_back", nil)
    compare_timestamps(command_id)

    render plain: DateTime.now.utc.iso8601
  end

  def wait_for_publish_posts_job
    fill_current_user

    utc_now = DateTime.now.utc
    timezone = TZInfo::Timezone.get(@current_user.user_settings.timezone)
    local_datetime = timezone.utc_to_local(utc_now)
    local_date_str = ScheduleHelper::date_str(local_datetime)

    poll_count = 0
    while true
      is_scheduled_for_date = PublishPostsJob::is_scheduled_for_date(@current_user.id, local_date_str)
      break unless is_scheduled_for_date

      sleep(0.1)
      poll_count += 1
      raise "Job didn't run" if poll_count >= 10
    end

    render plain: "OK"
  end

  def set_email_metadata
    value = params[:value]
    TestSingleton.find("email_metadata").update_attribute(:value, value)
    render plain: "OK"
  end

  def assert_email_count_with_metadata
    value = params[:value]
    count = params[:count].to_i
    last_timestamp = params[:last_timestamp]
    last_tag = params[:last_tag]
    api_token = Rails.application.credentials.postmark_api_sandbox_token
    postmark_client = Postmark::ApiClient.new(api_token)

    poll_count = 0
    while true
      messages = postmark_client.get_messages(count: 100, offset: 0, metadata_test: value)
      if messages&.length == count
        #noinspection RubyNilAnalysis
        if count != 0 && messages&.first[:metadata]["server_timestamp"] != last_timestamp
          raise "Last message timestamp doesn't match: #{messages&.first[:metadata]["server_timestamp"]}"
        end

        if count != 0 && messages&.first[:tag] != last_tag
          raise "Last message tag doesn't match: #{messages&.first[:tag]}"
        end

        return render plain: "OK"
      end

      sleep(1)
      poll_count += 1
      raise "Email count doesn't match: expected #{count}, actual #{messages&.length}" if poll_count >= 20
    end
  end

  def delete_email_metadata
    TestSingleton.find("email_metadata").update_attribute(:value, nil)
    render plain: "OK"
  end

  def destroy_user_subscriptions
    fill_current_user
    @current_user.destroy_subscriptions_recursively!
    render plain: "OK"
  end

  def reschedule_user_job
    fill_current_user

    query = <<-SQL
      delete from delayed_jobs
      where (handler like '%class: PublishPostsJob%' or
          handler like '%class: EmailInitialItemJob%' or
          handler like '%class: EmailPostsJob%' or
          handler like '%class: EmailFinalItemJob%') and
        handler like concat('%', $1::text, '%')
    SQL
    ActiveRecord::Base.connection.exec_query(query, "SQL", [@current_user.id])

    PublishPostsJob.initial_schedule(@current_user)
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
    PublishPostsJob::destroy_user_jobs(user.id)
    user.destroy!
    render plain: "OK"
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
    TestSingleton.uncached do
      poll_count = 0
      while true
        worker_command_id_row = TestSingleton.find("time_travel_command_id")
        break if worker_command_id_row.value == command_id.to_s

        sleep(0.1)
        poll_count += 1
        raise "Worker didn't time travel (command #{command_id})" if poll_count >= 30
      end
    end

    web_timestamp = DateTime.now.utc
    worker_timestamp_row = TestSingleton.find("time_travel_timestamp")
    worker_timestamp = DateTime.parse(worker_timestamp_row.value).to_time
    difference = (worker_timestamp - web_timestamp).abs
    if difference > 60
      raise "Web timestamp #{web_timestamp} doesn't match worker timestamp #{worker_timestamp}"
    end
  end
end
