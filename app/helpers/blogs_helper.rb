module BlogsHelper
  def BlogsHelper.feed_url(request, blog)
    "#{request.protocol}#{request.host_with_port}/blogs/#{blog.id}/feed"
  end

  def BlogsHelper.setup_url(request, blog)
    "#{request.protocol}#{request.host_with_port}/blogs/#{blog.id}/setup"
  end

  def BlogsHelper.days_of_week_from_params(schedule_params)
    days_of_week = []
    days_of_week << 'mon' if schedule_params[:schedule_mon] == '1'
    days_of_week << 'tue' if schedule_params[:schedule_tue] == '1'
    days_of_week << 'wed' if schedule_params[:schedule_wed] == '1'
    days_of_week << 'thu' if schedule_params[:schedule_thu] == '1'
    days_of_week << 'fri' if schedule_params[:schedule_fri] == '1'
    days_of_week << 'sat' if schedule_params[:schedule_sat] == '1'
    days_of_week << 'sun' if schedule_params[:schedule_sun] == '1'
    days_of_week
  end

  def BlogsHelper.create(start_page_id, start_feed_id, start_feed_url, name, current_user)
    Blog.transaction do
      blog = current_user.blogs.new
      blog.name = name
      blog.url = start_feed_url
      blog.fetch_status = :in_progress
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

    def save_status(status_str)
      Blog.transaction do
        #noinspection RailsChecklist05
        blog = Blog.find_by_id(@blog_id)
        raise BlogDeletedError unless blog

        blog.update_column(:fetch_progress, status_str)
        ActionCable.server.broadcast("discovery_#{@blog_id}", { status: status_str })
      end
    end

    def save_count(count)
      Blog.transaction do
        #noinspection RailsChecklist05
        blog = Blog.find_by_id(@blog_id)
        raise BlogDeletedError unless blog

        blog.update_column(:fetch_count, count)
        ActionCable.server.broadcast("discovery_#{@blog_id}", { count: count })
      end
    end
  end
end
