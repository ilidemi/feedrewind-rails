class UpdateRssJob < ApplicationJob
  queue_as :default

  PACIFIC_TIME_ZONE = 'Pacific Time (US & Canada)'

  def perform(blog_id)
    day_of_week = Date.today
                      .in_time_zone(PACIFIC_TIME_ZONE)
                      .strftime('%a')
                      .downcase
    if Schedule.find_by(blog_id: blog_id, day_of_week: day_of_week)
      UpdateRssService.update_rss(blog_id)
    end
    blog = Blog.find_by(id: blog_id)
    if blog and blog.posts.where(is_published: false).count > 0
      UpdateRssJob.schedule_for_tomorrow(blog_id)
    end
  end

  def self.schedule_for_tomorrow(blog_id)
    next_run = Date.tomorrow.in_time_zone(PACIFIC_TIME_ZONE)
    UpdateRssJob
      .set(wait_until: next_run)
      .perform_later(blog_id)
  end

  def max_attempts
    5
  end
end
