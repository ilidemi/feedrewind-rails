class ResetFailedBlogsJob < ApplicationJob
  queue_as "reset_failed_blogs"

  def perform(enqueue_next)
    utc_now = DateTime.now.utc
    cutoff = utc_now.advance(days: -30)

    Blog::reset_failed_blogs(cutoff)

    if enqueue_next
      next_run = utc_now.advance(days: 1).midnight
      ResetFailedBlogsJob.set(wait_until: next_run).perform_later(true)
    end
  end
end

