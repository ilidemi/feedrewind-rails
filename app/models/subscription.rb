class Subscription < ApplicationRecord
  include RandomId, Discardable

  belongs_to :user, optional: true
  belongs_to :blog
  has_many :subscription_posts, dependent: :destroy
  has_many :schedules, dependent: :destroy
  has_one :current_rss, dependent: :destroy

  BlogNotSupported = Struct.new(:blog)

  def Subscription::create_for_blog(blog, current_user)
    if %w[crawled_confirmed manually_inserted].include?(blog.status)
      Subscription.transaction do
        subscription = Subscription.create!(
          user_id: current_user&.id,
          blog_id: blog.id,
          name: blog.name,
          status: "setup"
        )

        now = Time.current
        subscription_posts_fields = blog.blog_posts.map do |blog_post|
          {
            subscription_id: subscription.id,
            blog_post_id: blog_post.id,
            is_published: false,
            created_at: now,
            updated_at: now
          }
        end
        SubscriptionPost.insert_all!(subscription_posts_fields)

        subscription
      end
    elsif %w[crawl_failed crawled_looks_wrong update_from_feed_failed].include?(blog.status)
      BlogNotSupported.new(blog)
    else
      Subscription.create!(
        user_id: current_user&.id,
        blog_id: blog.id,
        name: blog.name,
        status: "waiting_for_blog"
      )
    end
  end
end
