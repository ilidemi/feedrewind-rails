class ResetFailedBlogsJob < ApplicationJob
  queue_as :default

  def perform(enqueue_next)
    cutoff = DateService
      .now
      .advance(days: -30)

    Blog::reset_failed_blogs(cutoff)

    if enqueue_next
      ResetFailedBlogsJob.schedule_for_tomorrow(true)
    end
  end

  def queue_name
    "reset_failed_blogs"
  end
end

