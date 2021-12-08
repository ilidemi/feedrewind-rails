class DiscoveryChannel < ApplicationCable::Channel
  def subscribed
    stream_from "discovery_#{params[:blog_id]}"
  end

  def after_confirmation_sent
    transmit_status
    10.times do
      sleep(0.1)
      transmit_status
    end
  end

  private

  def transmit_status
    BlogCrawlProgress.uncached do
      blog_crawl_progress = BlogCrawlProgress.find_by(blog_id: params[:blog_id])
      return unless blog_crawl_progress

      Blog.uncached do
        if blog_crawl_progress.blog.status == "crawl_in_progress"
          transmit(
            {
              epoch: blog_crawl_progress.epoch,
              status: blog_crawl_progress.progress,
              count: blog_crawl_progress.count
            }
          )
        elsif %w[crawled crawl_failed].include?(blog_crawl_progress.blog.status)
          transmit({ done: true })
        end
      end
    end
  end
end
