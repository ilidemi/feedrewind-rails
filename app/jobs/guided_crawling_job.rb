require 'json'
require_relative '../lib/guided_crawling/guided_crawling'

GuidedCrawlingJobArgs = Struct.new(:start_feed_id)

class GuidedCrawlingJob < ApplicationJob
  queue_as :default

  def perform(blog_id, args_json)
    begin
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      args = JSON.parse(args_json, object_class: GuidedCrawlingJobArgs)
      start_feed = StartFeed.find(args.start_feed_id)
      start_page = start_feed.start_page
      start_blog = Blog.find(blog_id)
      has_previously_failed = Blog
        .where(feed_url: start_blog.feed_url)
        .where("version != #{Blog::LATEST_VERSION}")
        .order(version: :desc)
        .limit(1)
        .first
        &.status
        .in?(Blog::FAILED_STATUSES)

      crawl_ctx = CrawlContext.new
      http_client = HttpClient.new
      puppeteer_client = PuppeteerClient.new
      progress_saver = SubscriptionsHelper::ProgressSaver.new(blog_id, start_blog.feed_url)
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
        Blog.transaction do
          blog = Blog.find(blog_id)
          blog.init_crawled(
            blog_url, urls_titles_categories, categories, discarded_feed_entry_urls, curi_eq_cfg_hash
          )
          log_crawl_finished(blog, "crawl succeeded")
        end
        crawl_succeeded = true
      else
        Rails.logger.info("Historical links not found")
        blog_url = nil
        Blog.transaction do
          blog = Blog.find(blog_id)
          blog.status = "crawl_failed"
          blog.save!
          log_crawl_finished(blog, "crawl failed")
        end
        crawl_succeeded = false
      end

      finish_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      elapsed_seconds = finish_time - start_time
      AdminTelemetry.create!(
        key: crawl_succeeded ? "guided_crawling_job_success" : "guided_crawling_job_failure",
        value: elapsed_seconds,
        extra: {
          feed_url: start_feed.url
        }
      )

      slack_blog_url = NotifySlackJob::escape(blog_url || start_page&.url || start_blog.feed_url)
      slack_blog_name = NotifySlackJob::escape(start_blog.name)
      slack_verb = crawl_succeeded ? "succeeded" : "failed"
      NotifySlackJob.perform_later("Crawling *<#{slack_blog_url}|#{slack_blog_name}>* #{slack_verb} in #{elapsed_seconds.round(1)} seconds")

      if crawl_ctx.title_fetch_duration
        AdminTelemetry.create!(
          key: "crawling_title_fetch_duration",
          value: crawl_ctx.title_fetch_duration,
          extra: {
            feed_url: start_feed.url,
            requests_made: crawl_ctx.title_requests_made
          }
        )
      end
      if crawl_ctx.duplicate_fetches > 0
        AdminTelemetry.create!(
          key: "crawling_duplicate_requests",
          value: crawl_ctx.duplicate_fetches,
          extra: {
            feed_url: start_feed.url
          }
        )
      end
      if has_previously_failed
        AdminTelemetry.create!(
          key: "recrawl_status",
          value: crawl_succeeded ? 1 : 0,
          extra: {
            feed_url: start_feed.url
          }
        )
      end
    rescue ActiveRecord::RecordNotFound
      Rails.logger.warn("Record not found for blog #{blog_id}")
    ensure
      ActionCable.server.broadcast("discovery_#{blog_id}", { done: true })
      Rails.logger.info("discovery_#{blog_id} done: true")
    end
  end

  private

  def log_crawl_finished(blog, event_type)
    Subscription.with_discarded.where(blog_id: blog.id).each do |subscription|
      product_user_id = subscription.user ?
        subscription.user.product_user_id :
        subscription.anon_product_user_id
      wait_duration = blog.updated_at - subscription.created_at
      ProductEvent.atomic_create!(
        product_user_id: product_user_id,
        event_type: event_type,
        event_properties: {
          subscription_id: subscription.id,
          blog_url: blog.best_url,
          wait_duration: wait_duration
        }
      )
    end
  end
end
