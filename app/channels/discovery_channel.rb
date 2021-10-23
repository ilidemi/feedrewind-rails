class DiscoveryChannel < ApplicationCable::Channel
  def subscribed
    stream_from "discovery_#{params[:blog_id]}"

    transmit_status
    sleep(1)
    transmit_status
  end

  private

  def transmit_status
    Blog.uncached do
      blog = Blog.find_by(id: params[:blog_id])
      return unless blog

      if blog.status == "crawl_in_progress"
        transmit(
          {
            status: blog.fetch_progress,
            status_epoch: blog.fetch_progress_epoch,
            count: blog.fetch_count,
            count_epoch: blog.fetch_count_epoch
          }
        )
      elsif %w[crawled crawl_failed].include?(blog.status)
        transmit({ done: true })
      end
    end
  end
end
