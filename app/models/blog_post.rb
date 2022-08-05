class BlogPost < ApplicationRecord
  belongs_to :blog
  has_many :subscription_posts
  has_many :blog_post_categories, dependent: :destroy
end
