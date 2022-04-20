class ResetFailedBlogsJob < ApplicationJob
  queue_as "reset_failed_blogs"

  def perform(enqueue_next)
    cutoff = ScheduleHelper
      .now
      .date
      .advance(days: -30)

    Blog::reset_failed_blogs(cutoff)

    if enqueue_next
      ResetFailedBlogsJob.schedule_for_tomorrow(true)
    end
  end
end

