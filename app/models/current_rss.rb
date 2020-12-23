class CurrentRss < ApplicationRecord
  belongs_to :blog
  validates :body, presence: true
end
