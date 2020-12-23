class Blog < ApplicationRecord
  has_many :posts, dependent: :destroy
  has_many :schedules, dependent: :destroy
  has_one :current_rss, dependent: :destroy
  validates :name, presence: true
  validates :url, presence: true
  validates :posts_per_day, presence: true
end
