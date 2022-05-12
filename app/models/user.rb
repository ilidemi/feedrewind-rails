class User < ApplicationRecord
  include RandomId

  has_secure_password
  has_many :subscriptions, dependent: :destroy
  has_one :user_rss, dependent: :destroy
  has_many :blog_crawl_votes, dependent: :destroy
  validates_length_of :password, minimum: 8
  validates_presence_of :email
  validate :email_uniqueness
  before_create { generate_token(:auth_token) }

  private

  def generate_token(column)
    begin
      self[column] = SecureRandom.urlsafe_base64
    end while User.exists?(column => self[column])
  end

  def email_uniqueness
    if User.where(["email = ? and password_digest is not null", self.email]).exists?
      self.errors.add(:base, "We already have an account registered with that email address.")
    end
  end
end
