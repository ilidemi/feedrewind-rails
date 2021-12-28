class Blog < ApplicationRecord
  LATEST_VERSION = 1000000

  include RandomId

  has_one :blog_crawl_client_token, dependent: :destroy
  has_one :blog_crawl_progress, dependent: :destroy
  has_many :blog_crawl_votes, dependent: :destroy
  has_many :blog_posts, dependent: :destroy

  def destroy_recursively!
    Blog.transaction do
      Blog.uncached do
        blog_crawl_client_token.destroy!
        blog_crawl_progress.destroy!
        blog_crawl_votes.destroy_all

        subscriptions = Subscription.with_discarded.where(blog_id: id)
        subscription_posts_relations = subscriptions
          .includes(:subscription_posts)
          .map(&:subscription_posts)

        subscription_posts_count = subscription_posts_relations.map(&:length).sum
        Rails.logger.info("Destroying #{subscription_posts_count} subscription posts")
        subscription_posts_relations.each do |subscription_posts|
          subscription_posts.destroy_all
        end

        Rails.logger.info("Destroying #{subscriptions.length} subscriptions")
        subscriptions.each do |subscription|
          subscription.discard!
          subscription.destroy_discarded!
        end

        blog_posts.destroy_all
        destroy!
      end
    end
  end
end
