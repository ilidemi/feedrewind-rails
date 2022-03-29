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

      posts_text = params[:posts]
      post_lines = posts_text.split("\n").map(&:strip)
      post_lines.each do |post_line|
        unless %w[http:// https://].any? { |prefix| post_line.start_with?(prefix) }
          raise "Line doesn't start with a full url: #{post_line}"
        end
        unless post_line.include?(" ")
          raise "Line doesn't have a space between url and title: #{post_line}"
        end
      end
      post_lines.reverse! if direction == "newest_first"
      post_urls_titles = post_lines.map do |line|
        url, _, title = line.partition(" ")
        { url: url, title: title }
      end

      same_hosts = params[:same_hosts].split("\n").map(&:strip)
      expect_tumblr_paths = params[:expect_tumblr_paths]
      curi_eq_cfg = CanonicalEqualityConfig.new(same_hosts.to_set, expect_tumblr_paths)

      update_action = params[:update_action]

      feed_result = fetch_feed_at_url(feed_url, Rails.logger)
      raise "Couldn't fetch feed" unless feed_result.is_a?(Page)

      feed_link = to_canonical_link(feed_url, Rails.logger)
      parsed_feed = parse_feed(feed_result.content, feed_link.uri, Rails.logger)

      post_curis_set = post_urls_titles
        .map { |url_title| to_canonical_link(url_title[:url], Rails.logger) }
        .map(&:curi)
        .to_canonical_uri_set(curi_eq_cfg)
      discarded_feed_entry_urls = parsed_feed
        .entry_links
        .to_a
        .filter { |entry_link| !post_curis_set.include?(entry_link.curi) }
        .map(&:url)

      Blog.transaction do
        old_blog = Blog.find_by(feed_url: feed_url, version: Blog::LATEST_VERSION)
        if old_blog
          old_blog.version = Blog::get_downgrade_version(feed_url)
          old_blog.save!
        end

        blog = Blog.create!(
          name: name,
          feed_url: feed_url,
          status: "manually_inserted",
          status_updated_at: DateTime.now,
          version: Blog::LATEST_VERSION,
          update_action: update_action
        )

        post_urls_titles.each_with_index do |url_title, index|
          BlogPost.create!(
            blog_id: blog.id,
            index: index,
            url: url_title[:url],
            title: url_title[:title]
          )
        end

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
end
