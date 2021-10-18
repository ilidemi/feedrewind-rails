class UpdateRssJob < ApplicationJob
  queue_as :default

  def perform(blog_id)
    day_of_week = DateService.day_of_week
    blog = Blog.find_by(id: blog_id)
    if blog
      if !blog.is_paused and Schedule.find_by(blog_id: blog_id, day_of_week: day_of_week)
        UpdateRssService.update_rss(blog_id)
      end
      if blog.posts.where(is_published: false).count > 0
        UpdateRssJob.schedule_for_tomorrow(blog_id)
      end
    end
  end

  def self.schedule_for_tomorrow(blog_id)
    next_run = DateTime
      .now
      .in_time_zone(DateService::PACIFIC_TIME_ZONE)
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
