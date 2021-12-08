module BlogsHelper
  def BlogsHelper.setup_path(blog)
    "/blogs/#{blog.id}/setup"
  end

  def BlogsHelper.posts_path(blog)
    "/blogs/#{blog.id}/posts"
  end

  def BlogsHelper.confirm_path(blog)
    "/blogs/#{blog.id}/confirm"
  end

  def BlogsHelper.mark_wrong_path(blog)
    "/blogs/#{blog.id}/mark_wrong"
  end

  def BlogsHelper.schedule_path(blog)
    "/blogs/#{blog.id}/schedule"
  end

  def BlogsHelper.blog_url(blog)
    # TODO: this should become feeduler.com
    "https://rss-catchup.herokuapp.com/blogs/#{blog.id}"
  end

  def BlogsHelper.blog_path(blog)
    "/blogs/#{blog.id}"
  end

  # This has to be a full url because we're showing it to the user to select and copy
  def BlogsHelper.feed_url(request, blog)
    "#{request.protocol}#{request.host_with_port}/blogs/#{blog.id}/feed"
  end

  def BlogsHelper.create(start_page_id, start_feed_id, start_feed_url, name, current_user)
    Blog.transaction do
      blog = Blog.new
      blog.user_id = current_user&.id
      blog.name = name
      blog.url = start_feed_url
      blog.status = "crawl_in_progress"
      blog.save!

      blog_crawl_progress = BlogCrawlProgress.new(blog_id: blog.id, epoch: 0)
      blog_crawl_progress.save!

      GuidedCrawlingJob.perform_later(
        blog.id, GuidedCrawlingJobArgs.new(start_page_id, start_feed_id).to_json
      )

      blog
    end
  end

  class BlogDeletedError < StandardError
  end

  class ProgressSaver
    def initialize(blog_id)
      @blog_id = blog_id
      @last_epoch_timestamp = Time.now.utc
    end

    def save_status_and_count(status_str, count)
      BlogCrawlProgress.transaction do
        #noinspection RailsChecklist05
        blog_crawl_progress = BlogCrawlProgress.find(@blog_id)
        raise BlogDeletedError unless blog_crawl_progress

        blog_crawl_progress.update_column(:progress, status_str)
        blog_crawl_progress.update_column(:count, count)
        new_epoch = blog_crawl_progress.epoch + 1
        blog_crawl_progress.update_column(:epoch, new_epoch)
        update_epoch_times(blog_crawl_progress)
        ActionCable.server.broadcast(
          "discovery_#{@blog_id}",
          { epoch: new_epoch, status: status_str, count: count }
        )
        Rails.logger.info("discovery_#{@blog_id} epoch: #{new_epoch} status: #{status_str} count: #{count}")
      end
    end

    def save_status(status_str)
      BlogCrawlProgress.transaction do
        #noinspection RailsChecklist05
        blog_crawl_progress = BlogCrawlProgress.find(@blog_id)
        raise BlogDeletedError unless blog_crawl_progress

        blog_crawl_progress.update_column(:progress, status_str)
        new_epoch = blog_crawl_progress.epoch + 1
        blog_crawl_progress.update_column(:epoch, new_epoch)
        update_epoch_times(blog_crawl_progress)
        ActionCable.server.broadcast("discovery_#{@blog_id}", { epoch: new_epoch, status: status_str })
        Rails.logger.info("discovery_#{@blog_id} epoch: #{new_epoch} status: #{status_str}")
      end
    end

    def save_count(count)
      BlogCrawlProgress.transaction do
        #noinspection RailsChecklist05
        blog_crawl_progress = BlogCrawlProgress.find(@blog_id)
        raise BlogDeletedError unless blog_crawl_progress

        blog_crawl_progress.update_column(:count, count)
        new_epoch = blog_crawl_progress.epoch + 1
        blog_crawl_progress.update_column(:epoch, new_epoch)
        update_epoch_times(blog_crawl_progress)
        ActionCable.server.broadcast("discovery_#{@blog_id}", { epoch: new_epoch, count: count })
        Rails.logger.info("discovery_#{@blog_id} epoch: #{new_epoch} count: #{count}")
      end
    end

    private

    def update_epoch_times(blog_crawl_progress)
      new_epoch_timestamp = Time.now.utc
      new_epoch_time = (new_epoch_timestamp - @last_epoch_timestamp).round(3)
      if blog_crawl_progress.epoch_times
        new_epoch_times = "#{blog_crawl_progress.epoch_times};#{new_epoch_time}"
      else
        new_epoch_times = "#{new_epoch_time}"
      end
      blog_crawl_progress.update_column(:epoch_times, new_epoch_times)
      @last_epoch_timestamp = new_epoch_timestamp
    end
  end
end
