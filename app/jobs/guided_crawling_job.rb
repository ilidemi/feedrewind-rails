require 'json'
require_relative '../lib/guided_crawling/guided_crawling'
require_relative '../services/update_rss_service'

GuidedCrawlingJobArgs = Struct.new(:start_page_id, :start_feed_id)

class GuidedCrawlingJob < ApplicationJob
  queue_as :default

  def perform(blog_id, args_json)
    begin
      args = JSON.parse(args_json, object_class: GuidedCrawlingJobArgs)
      start_page = args.start_page_id ? StartPage.find(args.start_page_id) : nil
      start_feed = StartFeed.find(args.start_feed_id)

      crawl_ctx = CrawlContext.new
      http_client = HttpClient.new
      puppeteer_client = PuppeteerClient.new
      progress_saver = BlogsHelper::ProgressSaver.new(blog_id)
      begin
        guided_crawl_result = guided_crawl(
          start_page, start_feed, crawl_ctx, http_client, puppeteer_client, progress_saver, Rails.logger
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
          blog = Blog.find(blog_id)
          guided_crawl_result.historical_result.links.each_with_index do |link, post_index|
            blog.posts.new(link: link.url, order: -post_index, title: link.url, date: "", is_published: false)
          end
          blog.status = "crawled"
          blog.save!
        end
      else
        Rails.logger.info("Historical links not found")
        Blog.transaction do
          blog = Blog.find(blog_id)
          blog.status = "crawl_failed"
          blog.save!
        end
      end
    rescue ActiveRecord::RecordNotFound
      Rails.logger.warn("Record not found for blog #{blog_id}")
    ensure
      ActionCable.server.broadcast("discovery_#{blog_id}", { done: true })
      Rails.logger.info("discovery_#{blog_id} done: true")
    end
  end
end

