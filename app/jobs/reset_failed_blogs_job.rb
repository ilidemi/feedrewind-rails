class ResetFailedBlogsJob < ApplicationJob
  queue_as :default

  def perform(enqueue_next)
    cutoff = DateService
      .now
      .advance(days: -30)

    blogs_to_reset = Blog
      .where("status = 'crawl_failed' or status = 'crawled_looks_wrong'")
      .where(["version = ?", Blog::LATEST_VERSION])
      .where(["status_updated_at < ?", cutoff])

    Rails.logger.info("Resetting #{blogs_to_reset.length} failed blogs")

    blogs_to_reset.each do |blog|
      prev_version = Blog
        .where(["feed_url = ?", blog.feed_url])
        .where(["version != ?", Blog::LATEST_VERSION])
        .order(version: :desc)
        .limit(1)
        .first
        &.version || 0
      blog.version = prev_version + 1
      Rails.logger.info("Blog #{blog.id} -> new version #{blog.version}")
      blog.save!
    end

    def queue_name
      "reset_failed_blogs"
    end

    if enqueue_next
      ResetFailedBlogsJob.schedule_for_tomorrow(true)
    end
  end
end

