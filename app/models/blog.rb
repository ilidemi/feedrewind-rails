class Blog < ApplicationRecord
  belongs_to :user
  has_many :posts, dependent: :destroy
  has_many :schedules, dependent: :destroy
  has_one :current_rss, dependent: :destroy
  validates :name, presence: true
  validates :url, presence: true
end
