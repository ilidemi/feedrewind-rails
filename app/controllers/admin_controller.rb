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
      post_lines = posts_text.split("\n")
      post_lines.each do |post_line|
        unless %w[http:// https://].any? { |prefix| post_line.start_with?(prefix) }
          raise "Line doesn't start with a full url: #{post_line}"
        end
        unless post_line.include?(" ")
          raise "Line doesn't have a space between url and title: #{post_line}"
        end
      end
      post_lines.reverse! if direction == "newest_first"

      Blog.transaction do
        blog = Blog.create!(
          name: name,
          feed_url: feed_url,
          status: "manually_inserted",
          status_updated_at: DateTime.now,
          version: Blog::LATEST_VERSION
        )

        post_lines.each_with_index do |line, index|
          post_url, _, post_title = line.partition(" ")
          BlogPost.create!(
            blog_id: blog.id,
            index: index,
            url: post_url,
            title: post_title
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
