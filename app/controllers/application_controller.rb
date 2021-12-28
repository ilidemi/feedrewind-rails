class ApplicationController < ActionController::Base
  private

  def current_user
    @current_user ||= User.find(session[:user_id]) if session[:user_id]
  end

  helper_method :current_user

  def authorize
    redirect_to login_path, alert: "Not authorized" if current_user.nil?
  end

  def fill_current_user
    current_user
  end

  BlogNotSupported = Struct.new(:blog)

  def create_subscription(start_page_id, start_feed_id, start_feed_url, name, current_user)
    blog = Blog.find_by(feed_url: start_feed_url, version: Blog::LATEST_VERSION)

    unless blog
      begin
        Rails.logger.info("Creating a new blog for feed_url #{start_feed_url}")
        Blog.transaction do
          blog = Blog.create!(
            name: name,
            feed_url: start_feed_url,
            status: "crawl_in_progress",
            status_updated_at: DateTime.now,
            version: Blog::LATEST_VERSION
          )

          BlogCrawlProgress.create!(blog_id: blog.id, epoch: 0)

          GuidedCrawlingJob.perform_later(
            blog.id, GuidedCrawlingJobArgs.new(start_page_id, start_feed_id).to_json
          )
        end
      rescue ActiveRecord::RecordNotUnique
        blog = Blog.find_by(feed_url: start_feed_url, version: Blog::LATEST_VERSION)
        unless blog
          raise "Blog #{start_feed_url} with latest version didn't exist, then existed, now doesn't exist"
        end
      end
    end

    if blog.status == "crawled_confirmed"
      Subscription.transaction do
        subscription = Subscription.create!(
          user_id: current_user&.id,
          blog_id: blog.id,
          name: name,
          status: "setup"
        )

        blog.blog_posts.each do |blog_post|
          SubscriptionPost.create!(
            subscription_id: subscription.id,
            blog_post_id: blog_post.id,
            is_published: false
          )
        end

        subscription
      end
    elsif %w[crawl_failed crawled_looks_wrong].include?(blog.status)
      BlogNotSupported.new(blog)
    else
      Subscription.create!(
        user_id: current_user&.id,
        blog_id: blog.id,
        name: name,
        status: "waiting_for_blog"
      )
    end
  end
end
