require 'math'
require 'set'
require_relative '../lib/guided_crawling/feed_discovery'
require_relative '../lib/guided_crawling/canonical_link'
require_relative '../lib/guided_crawling/crawling'

class AdminController < ApplicationController
  before_action :authorize_admin
  layout "admin"

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

  Dashboard = Struct.new(:key, :y_scale, :items)
  DashboardDate = Struct.new(:date_str)
  DashboardBar = Struct.new(:value, :value_percent, :hover)

  def dashboard
    week_ago = DateTime.now.utc.advance(days: -6).beginning_of_day
    telemetries = AdminTelemetry
      .all
      .where(["created_at > ?", week_ago])
      .order("created_at")
    telemetries_by_key = {}
    telemetries.each do |telemetry|
      unless telemetries_by_key.key?(telemetry.key)
        telemetries_by_key[telemetry.key] = []
      end
      telemetries_by_key[telemetry.key] << telemetry
    end

    @dashboards = []
    priority_keys = %w[guided_crawling_job_success guided_crawling_job_failure]
    sorted_keys = telemetries_by_key
      .keys
      .sort_by { |key| [priority_keys.index(key) || priority_keys.length, key] }
    sorted_keys.each do |key|
      key_telemetries = telemetries_by_key[key]

      y_max = 0
      key_telemetries.each do |telemetry|
        y_max = [telemetry.value, y_max].max
      end
      if y_max > 0
        y_max_10 = 10.0 ** Math.log10(y_max).ceil
        if y_max_10 / y_max >= 5
          y_scale_max = y_max_10 / 5
        elsif y_max_10 / y_max >= 2
          y_scale_max = y_max_10 / 2
        else
          y_scale_max = y_max_10
        end
      else
        y_scale_max = 1.0
      end
      y_scale = (0..10).map do |i|
        ActiveSupport::NumberHelper.number_to_rounded(
          y_scale_max * (10 - i) / 10,
          strip_insignificant_zeros: true
        )
      end

      items = []
      prev_date = nil
      prev_date_str = nil
      key_telemetries.each do |telemetry|
        date_str = telemetry.created_at.strftime("%Y-%m-%d")
        if date_str != prev_date_str
          if prev_date.nil?
            prev_date = telemetry.created_at
            prev_date_str = date_str
            items << DashboardDate.new(date_str)
          else
            while prev_date_str != date_str
              prev_date = prev_date.advance(days: 1)
              prev_date_str = prev_date.strftime("%Y-%m-%d")
              items << DashboardDate.new(prev_date_str)
            end
          end
        end

        formatted_value =
          ActiveSupport::NumberHelper.number_to_rounded(telemetry.value, strip_insignificant_zeros: true)
        if telemetry.value >= 0
          value_percent = telemetry.value * 100 / y_scale_max
        else
          value_percent = 5
        end
        hover = (telemetry.extra || {})
          .merge(
            {
              value: telemetry.value,
              timestamp: telemetry.created_at.strftime("%T %Z")
            }
          )
          .to_a
          .map { |k, v| "#{k}: #{v}" }
          .join("\n")
        items << DashboardBar.new(formatted_value, value_percent, hover)
      end

      @dashboards << Dashboard.new(key, y_scale, items)
    end
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
