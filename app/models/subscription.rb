class Subscription < ApplicationRecord
  include RandomId, Discardable

  belongs_to :user, optional: true
  belongs_to :blog
  has_many :subscription_posts, dependent: :destroy
  has_many :schedules, dependent: :destroy
  has_one :subscription_rss, dependent: :destroy
  has_many :postmark_messages, dependent: :destroy

  BlogNotSupported = Struct.new(:blog)

  def Subscription::create_for_blog(blog, current_user)
    if %w[crawl_failed crawled_looks_wrong update_from_feed_failed].include?(blog.status)
      BlogNotSupported.new(blog)
    else
      Subscription.create!(
        user_id: current_user&.id,
        blog_id: blog.id,
        name: blog.name,
        status: "waiting_for_blog",
        is_paused: false,
        schedule_version: 0,
      )
    end
  end

  def create_subscription_posts_from_category_raw!(category_id)
    query = <<-SQL
      insert into subscription_posts (subscription_id, blog_post_id, published_at, created_at, updated_at)
      select $1, blog_post_id, null, $2, $2
      from blog_post_category_assignments
      where category_id = $3;
    SQL
    ActiveRecord::Base.connection.exec_query(query, "SQL", [self.id, Time.current, category_id])
  end

  def create_subscription_posts_from_ids_raw!(blog_post_ids)
    # exec_query doesn't take arrays so blog_post_ids should be sanitized really well
    query = <<-SQL
      insert into subscription_posts (subscription_id, blog_post_id, published_at, created_at, updated_at)
      select $1, id, null, $2, $2
      from blog_posts
      where blog_id = $3 and id in (#{blog_post_ids.map(&:to_s).join(", ")});
    SQL
    ActiveRecord::Base.connection.exec_query(query, "SQL", [self.id, Time.current, self.blog_id])
  end
end
