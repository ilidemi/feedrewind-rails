require 'active_support/testing/time_helpers'

class TestController < ApplicationController
  extend ActiveSupport::Testing::TimeHelpers

  def travel_to_1am
    date = ScheduleHelper.now.date
    date = date.change(hour: 1)
    self.class.travel_to(date)
    render plain: "#{ScheduleHelper::now.date}"
  end

  def travel_to_12pm
    date = ScheduleHelper.now.date
    date = date.change(hour: 12)
    self.class.travel_to(date)
    render plain: "#{ScheduleHelper::now.date}"
  end

  def travel_1day
    self.class.travel(1.day)
    render plain: "#{ScheduleHelper::now.date}"
  end

  def travel_31days
    self.class.travel(31.day)
    render plain: "#{ScheduleHelper::now.date}"
  end

  def travel_back
    self.class.travel_back
    render plain: "#{ScheduleHelper::now.date}"
  end

  def run_update_rss_job
    UpdateRssJob.new.perform(params[:subscription_id])
    render plain: "OK"
  end

  def run_reset_failed_blogs_job
    ResetFailedBlogsJob.new.perform(false)
    render plain: "OK"
  end
end
