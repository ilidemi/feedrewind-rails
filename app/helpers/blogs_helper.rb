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
      blog.fetch_progress_epoch = 0
      blog.fetch_count_epoch = 0
      blog.save!

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
    end

    def save_status_and_count(status_str, count)
      Blog.transaction do
        #noinspection RailsChecklist05
        blog = Blog.find_by_id(@blog_id)
        raise BlogDeletedError unless blog

        blog.update_column(:fetch_progress, status_str)
        blog.update_column(:fetch_count, count)
        new_progress_epoch = blog.fetch_progress_epoch + 1
        new_count_epoch = blog.fetch_count_epoch + 1
        blog.update_column(:fetch_progress_epoch, new_progress_epoch)
        blog.update_column(:fetch_count_epoch, new_count_epoch)
        ActionCable.server.broadcast(
          "discovery_#{@blog_id}",
          { status: status_str, status_epoch: new_progress_epoch, count: count, count_epoch: new_count_epoch }
        )
        Rails.logger.info("discovery_#{@blog_id} status: #{status_str} status_epoch: #{new_progress_epoch} count: #{count} count_epoch: #{new_count_epoch}")
      end
    end

    def save_status(status_str)
      Blog.transaction do
        #noinspection RailsChecklist05
        blog = Blog.find_by_id(@blog_id)
        raise BlogDeletedError unless blog

        blog.update_column(:fetch_progress, status_str)
        new_epoch = blog.fetch_progress_epoch + 1
        blog.update_column(:fetch_progress_epoch, new_epoch)
        ActionCable.server.broadcast("discovery_#{@blog_id}", { status: status_str, status_epoch: new_epoch })
        Rails.logger.info("discovery_#{@blog_id} status: #{status_str} status_epoch: #{new_epoch}")
      end
    end

    def save_count(count)
      Blog.transaction do
        #noinspection RailsChecklist05
        blog = Blog.find_by_id(@blog_id)
        raise BlogDeletedError unless blog

        blog.update_column(:fetch_count, count)
        new_epoch = blog.fetch_count_epoch + 1
        blog.update_column(:fetch_count_epoch, new_epoch)
        ActionCable.server.broadcast("discovery_#{@blog_id}", { count: count, count_epoch: new_epoch })
        Rails.logger.info("discovery_#{@blog_id} count: #{count} count_epoch: #{new_epoch}")
      end
    end
  end
end
