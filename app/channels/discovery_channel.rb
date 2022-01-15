require_relative 'application_cable/application_cable_hack'

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
      unless blog_crawl_progress
        Rails.logger.info("Blog #{params[:blog_id]} crawl progress not found")
        return
      end

      Blog.uncached do
        blog_status = blog_crawl_progress.blog.status
        if blog_status == "crawl_in_progress"
          Rails.logger.info("Blog #{params[:blog_id]} crawl in progress (epoch #{blog_crawl_progress.epoch})")
          transmit(
            {
              epoch: blog_crawl_progress.epoch,
              status: blog_crawl_progress.progress,
              count: blog_crawl_progress.count
            }
          )
        elsif %w[crawled_voting crawl_failed].include?(blog_status)
          Rails.logger.info("Blog #{params[:blog_id]} crawl done")
          transmit({ done: true })
        else
          Rails.logger.info("Unexpected blog status: #{blog_status}")
          transmit({ done: true })
        end
      end
    end
  end
end
