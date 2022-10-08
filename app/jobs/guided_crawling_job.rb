require 'json'
require_relative '../lib/guided_crawling/guided_crawling'

GuidedCrawlingJobArgs = Struct.new(:start_feed_id)

class GuidedCrawlingJob < ApplicationJob
  queue_as :default

  def perform(blog_id, args_json)
    begin
      args = JSON.parse(args_json, object_class: GuidedCrawlingJobArgs)
      start_feed = StartFeed.find(args.start_feed_id)
      start_page = start_feed.start_page

      crawl_ctx = CrawlContext.new
      http_client = HttpClient.new
      puppeteer_client = PuppeteerClient.new
      progress_saver = SubscriptionsHelper::ProgressSaver.new(blog_id)
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
        blog_url = guided_crawl_result.historical_result.blog_link.url
        categories_list_by_link = CanonicalUriMap.new(guided_crawl_result.curi_eq_cfg)
        categories = []
        post_curis_set = CanonicalUriSet.new(
          guided_crawl_result.historical_result.links.map(&:curi),
          guided_crawl_result.curi_eq_cfg
        )
        if guided_crawl_result.historical_result.post_categories
          guided_crawl_result.historical_result.post_categories.each do |category|
            added_count = 0
            category.post_links.each do |link|
              unless post_curis_set.include?(link.curi)
                Rails.logger.warn("Post from category is not present in the list: #{link.url}")
                next
              end
              categories_list_by_link.add(link, []) unless categories_list_by_link.include?(link.curi)
              categories_list_by_link[link.curi] << category.name
              added_count += 1
            end

            if added_count > 0
              categories << { name: category.name, is_top: category.is_top }
            end
          end
        end
        categories << { name: "Everything", is_top: true }
        urls_titles_categories = guided_crawl_result.historical_result.links.map do |link|
          link_categories = (categories_list_by_link[link.curi] || []) + ["Everything"]
          {
            url: link.url,
            title: link.title.value,
            categories: link_categories
          }
        end
        curi_eq_cfg_hash = {
          same_hosts: guided_crawl_result.curi_eq_cfg.same_hosts.to_a,
          expect_tumblr_paths: guided_crawl_result.curi_eq_cfg.expect_tumblr_paths
        }
        discarded_feed_entry_urls = guided_crawl_result.historical_result.discarded_feed_entry_urls
        blog = Blog.find(blog_id)
        blog.init_crawled(
          blog_url, urls_titles_categories, categories, discarded_feed_entry_urls, curi_eq_cfg_hash
        )
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
