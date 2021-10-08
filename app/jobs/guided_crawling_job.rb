require 'json'
require_relative '../lib/guided_crawling/guided_crawling'
require_relative '../services/update_rss_service'

GuidedCrawlingJobArgs = Struct.new(:blog_url)

class GuidedCrawlingJob < ApplicationJob
  queue_as :default

  def perform(blog_id, args_json)
    begin
      args = JSON.parse(args_json, object_class: GuidedCrawlingJobArgs)

      crawl_ctx = CrawlContext.new
      http_client = HttpClient.new
      puppeteer_client = PuppeteerClient.new
      progress_saver = BlogsHelper::ProgressSaver.new(blog_id)
      begin
        guided_crawl_result = guided_crawl(
          args.blog_url, crawl_ctx, http_client, puppeteer_client, progress_saver, Rails.logger
        )
        if guided_crawl_result&.historical_error
          error_lines = print_nice_error(guided_crawl_result.historical_error)
          error_lines.each do |line|
            Rails.logger.info(line)
          end
          guided_crawl_result = nil
        end
      rescue => e
        error_lines = print_nice_error(e)
        error_lines.each do |line|
          Rails.logger.info(line)
        end
        guided_crawl_result = nil
      end

      if guided_crawl_result&.historical_result
        Rails.logger.info("Guided crawling job succeeded, saving blog")
        Blog.transaction do
          blog = Blog.find_by_id!(blog_id)
          guided_crawl_result.historical_result.links.each_with_index do |link, post_index|
            blog.posts.new(link: link.url, order: -post_index, title: "", date: "", is_published: false)
          end
          blog.fetch_status = :succeeded
          blog.save!

          UpdateRssService.update_rss(blog_id)
          UpdateRssJob.schedule_for_tomorrow(blog_id)
        end
      else
        Rails.logger.info("Historical links not found")
        Blog.transaction do
          blog = Blog.find_by_id!(blog_id)
          blog.fetch_status = :failed
          blog.save!
        end
      end
    rescue ActiveRecord::RecordNotFound
      Rails.logger.warn("Record not found for blog #{blog_id}")
    ensure
      ActionCable.server.broadcast("discovery_#{blog_id}", { done: true })
    end
  end
end

