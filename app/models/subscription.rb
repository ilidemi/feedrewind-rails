class Subscription < ApplicationRecord
  include RandomId, Discardable

  belongs_to :user, optional: true
  belongs_to :blog
  has_many :subscription_posts, dependent: :destroy
  has_many :schedules, dependent: :destroy
  has_one :subscription_rss, dependent: :destroy

  BlogNotSupported = Struct.new(:blog)

  def Subscription::create_for_blog(blog, current_user)
    if %w[crawled_confirmed manually_inserted].include?(blog.status)
      Subscription.transaction do
        subscription = Subscription.create!(
          user_id: current_user&.id,
          blog_id: blog.id,
          name: blog.name,
          status: "setup",
          is_paused: false,
          version: 0
        )
        subscription.create_subscription_posts_raw!

        subscription
      end
    elsif %w[crawl_failed crawled_looks_wrong update_from_feed_failed].include?(blog.status)
      BlogNotSupported.new(blog)
    else
      Subscription.create!(
        user_id: current_user&.id,
        blog_id: blog.id,
        name: blog.name,
        status: "waiting_for_blog",
        is_paused: false,
        version: 0
      )
    end
  end

  def create_subscription_posts_raw!
    query = <<-SQL
      insert into subscription_posts (subscription_id, blog_post_id, published_at, created_at, updated_at)
      select $1, id, null, $2, $2
      from blog_posts
      where blog_id = $3;
    SQL
    ActiveRecord::Base.connection.exec_query(query, "SQL", [self.id, Time.current, self.blog_id])
  end
end
