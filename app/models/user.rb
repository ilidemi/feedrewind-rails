class User < ApplicationRecord
  has_secure_password
  has_many :subscriptions
  validates_uniqueness_of :email
  before_create { generate_token(:auth_token) }

  private

  def generate_token(column)
    begin
      self[column] = SecureRandom.urlsafe_base64
    end while User.exists?(column => self[column])
  end
end
