require 'json'
require_relative '../lib/guided_crawling/guided_crawling'
require_relative '../services/update_rss_service'

GuidedCrawlingJobArgs = Struct.new(:blog_url)

class GuidedCrawlingJob < ApplicationJob
  queue_as :default

  def perform(blog_id, args_json)
    begin
      args = JSON.parse(args_json, object_class: GuidedCrawlingJobArgs)
      blog = Blog.find(blog_id)

      crawl_ctx = CrawlContext.new
      http_client = HttpClient.new
      puppeteer_client = PuppeteerClient.new
      guided_crawl_result = guided_crawl(
        args.blog_url, crawl_ctx, http_client, puppeteer_client, Rails.logger
      )

      if guided_crawl_result.historical_result
        Blog.transaction do
          guided_crawl_result.historical_result.links.each_with_index do |link, post_index|
            blog.posts.new(link: link.url, order: -post_index, title: "", date: "", is_published: false)
          end
          blog.fetch_status = "succeeded"
          blog.save!

          UpdateRssService.update_rss(blog.id)
          UpdateRssJob.schedule_for_tomorrow(blog.id)
        end
      else
        Rails.logger.info("Historical links not found")
        blog.fetch_status = "failed"
        blog.save!
      end
    rescue ActiveRecord::RecordNotFound
      Rails.logger.warn("Record not found for blog #{blog_id}")
    end
  end
end

