class User < ApplicationRecord
  include RandomId

  has_secure_password
  has_one :user_settings, dependent: :destroy
  has_many :subscriptions, dependent: :destroy
  has_one :user_rss, dependent: :destroy
  has_many :blog_crawl_votes, dependent: :destroy
  has_one :postmark_bounced_user, dependent: :destroy # Hopefully zero, but up to one
  validates_length_of :password, minimum: 8
  validates_presence_of :email
  validate :email_uniqueness
  before_create { generate_auth_token }

  def destroy_subscriptions_recursively!
    User.transaction do
      User.uncached do
        subscriptions = Subscription.with_discarded.where(user_id: id)
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
      end
    end
  end

  def generate_auth_token
    begin
      self.auth_token = SecureRandom.urlsafe_base64
    end while User.exists?(auth_token: self.auth_token)
  end

  private

  def email_uniqueness
    if User.where(["id != ? and email = ? and password_digest is not null", self.id, self.email]).exists?
      self.errors.add(:base, "We already have an account registered with that email address.")
    end
  end
end
