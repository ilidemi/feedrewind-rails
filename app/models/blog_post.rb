class BlogPost < ApplicationRecord
  belongs_to :blog
  has_many :subscription_posts
end
