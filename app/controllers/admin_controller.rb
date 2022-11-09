require 'set'
require_relative '../lib/guided_crawling/feed_discovery'
require_relative '../lib/guided_crawling/canonical_link'
require_relative '../lib/guided_crawling/crawling'

class AdminController < ApplicationController
  before_action :authorize_admin

  def add_blog
  end

  def post_blog
    begin
      name = params[:name]

      feed_url = params[:feed_url]
      unless %w[http:// https://].any? { |prefix| feed_url.start_with?(prefix) }
        raise "Feed url is supposed to be full: #{feed_url}"
      end

      direction = params[:direction]

      post_urls_titles = parse_urls_labels(params[:posts])
      post_urls_titles.reverse! if direction == "newest_first"
      post_urls_set = Set.new(post_urls_titles.map { |post| post[:url] })

      post_urls_categories = parse_urls_labels(params[:post_categories])
      post_urls_categories.each do |url_category|
        unless post_urls_set.include?(url_category[:url])
          raise "Unknown categorized url: #{url_category[:url]}"
        end
      end

      top_categories = params[:top_categories].split(";")
      top_categories_set = top_categories.to_set
      post_categories = top_categories.clone
      post_categories_set = Set.new(post_categories)
      post_urls_categories.each do |url_category|
        next if post_categories_set.include?(url_category[:label])
        post_categories_set << url_category[:label]
        post_categories << url_category[:label]
      end

      top_categories_set << "Everything"
      post_categories << "Everything"
      post_categories_set << "Everything"
      post_urls_set.each do |post_url|
        post_urls_categories << { url: post_url, label: "Everything" }
      end

      same_hosts = params[:same_hosts].split("\n").map(&:strip)
      expect_tumblr_paths = params[:expect_tumblr_paths]
      curi_eq_cfg = CanonicalEqualityConfig.new(same_hosts.to_set, expect_tumblr_paths)

      update_action = params[:update_action]

      post_links = post_urls_titles
        .map { |url_title| to_canonical_link(url_title[:url], Rails.logger) }
      post_curis_set = post_links
        .map(&:curi)
        .to_canonical_uri_set(curi_eq_cfg)

      if params[:skip_feed_validation] == "1"
        discarded_feed_entry_urls = []
        missing_from_feed_entry_urls = []
      else
        crawl_ctx = CrawlContext.new
        http_client = HttpClient.new(false)
        feed_result = fetch_feed_at_url(feed_url, false, crawl_ctx, http_client, Rails.logger)
        raise "Couldn't fetch feed" unless feed_result.is_a?(Page)

        feed_link = to_canonical_link(feed_url, Rails.logger)
        parsed_feed = parse_feed(feed_result.content, feed_link.uri, Rails.logger)
        feed_entry_links = parsed_feed.entry_links.to_a

        discarded_feed_entry_urls = feed_entry_links
          .filter { |entry_link| !post_curis_set.include?(entry_link.curi) }
          .map(&:url)
        feed_curis_set = feed_entry_links
          .map(&:curi)
          .to_canonical_uri_set(curi_eq_cfg)
        last_feed_post_index = post_links.find_index do |post_link|
          canonical_uri_equal?(post_link.curi, feed_entry_links.last.curi, curi_eq_cfg)
        end
        missing_from_feed_entry_urls = post_links[last_feed_post_index..]
          .filter { |post_link| !feed_curis_set.include?(post_link.curi) }
          .map(&:url)
      end

      Blog.transaction do
        old_blog = Blog.find_by(feed_url: feed_url, version: Blog::LATEST_VERSION)
        if old_blog
          old_blog.version = Blog::get_downgrade_version(feed_url)
          old_blog.save!
        end

        now_utc = DateTime.now.utc

        blog = Blog.create!(
          name: name,
          feed_url: feed_url,
          url: params[:url],
          status: "manually_inserted",
          status_updated_at: now_utc,
          version: Blog::LATEST_VERSION,
          update_action: update_action
        )

        blog_posts_fields = []
        post_urls_titles.each_with_index do |url_title, index|
          blog_posts_fields <<
            {
              blog_id: blog.id,
              index: index,
              url: url_title[:url],
              title: url_title[:label],
              created_at: now_utc,
              updated_at: now_utc
            }
        end
        blog_posts_result = BlogPost.insert_all!(blog_posts_fields, returning: %w[id url])
        blog_post_ids_by_url = blog_posts_result.rows.to_h { |id, url| [url, id] }

        post_categories_fields = []
        post_categories.each_with_index do |category_name, index|
          post_categories_fields <<
            {
              blog_id: blog.id,
              name: category_name,
              index: index,
              is_top: top_categories_set.include?(category_name),
              created_at: now_utc,
              updated_at: now_utc
            }
        end
        post_categories_result = BlogPostCategory.insert_all!(post_categories_fields, returning: %w[id name])
        category_ids_by_name = post_categories_result.rows.to_h { |id, category_name| [category_name, id] }

        category_assignments_fields = post_urls_categories.map do |url_category|
          {
            blog_post_id: blog_post_ids_by_url[url_category[:url]],
            category_id: category_ids_by_name[url_category[:label]],
            created_at: now_utc,
            updated_at: now_utc
          }
        end
        BlogPostCategoryAssignment.insert_all!(category_assignments_fields)

        BlogPostLock.create!(blog_id: blog.id)

        BlogCanonicalEqualityConfig.create!(
          blog_id: blog.id,
          same_hosts: same_hosts,
          expect_tumblr_paths: expect_tumblr_paths
        )

        discarded_feed_entry_urls.each do |url|
          BlogDiscardedFeedEntry.create!(
            blog_id: blog.id,
            url: url
          )
        end

        missing_from_feed_entry_urls.each do |url|
          BlogMissingFromFeedEntry.create!(
            blog_id: blog.id,
            url: url
          )
        end

        @message = "Created \"#{blog.name}\" (#{blog.feed_url}) with #{blog.blog_posts.length} posts"
      end
    end
  rescue => e
    @message = print_nice_error(e)
  end

  private

  def print_nice_error(error)
    lines = [error.to_s]
    loop do
      if error.backtrace
        lines << "---"
        error.backtrace.each do |line|
          lines << line
        end
      end

      if error.cause
        error = error.cause
      else
        break
      end
    end

    lines.join("\n")
  end

  def parse_urls_labels(text)
    lines = text.split("\n").map(&:strip)
    lines.each do |post_line|
      unless %w[http:// https://].any? { |prefix| post_line.start_with?(prefix) }
        raise "Line doesn't start with a full url: #{post_line}"
      end
      unless post_line.include?(" ")
        raise "Line doesn't have a space between url and title: #{post_line}"
      end
    end
    urls_labels = lines.map do |line|
      url, _, label = line.partition(" ")
      { url: url, label: label }
    end
    urls_labels
  end
end
