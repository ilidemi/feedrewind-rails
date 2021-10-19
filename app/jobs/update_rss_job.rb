class UpdateRssJob < ApplicationJob
  queue_as :default

  def perform(blog_id)
    day_of_week = DateService.day_of_week
    blog = Blog.find_by(id: blog_id)
    if blog
      schedule = Schedule.find_by(blog_id: blog_id, day_of_week: day_of_week)
      if !blog.is_paused and schedule
        UpdateRssService.update_rss(blog_id, schedule.count)
      end
      if blog.posts.where(is_published: false).count > 0
        UpdateRssJob.schedule_for_tomorrow(blog_id)
      end
    end
  end

  def self.schedule_for_tomorrow(blog_id)
    next_run = DateService
      .now
      .advance(days: 1)
      .midnight
    UpdateRssJob
      .set(wait_until: next_run)
      .perform_later(blog_id)
  end

  def max_attempts
    5
  end
end
