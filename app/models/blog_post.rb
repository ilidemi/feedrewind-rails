class BlogPost < ApplicationRecord
  belongs_to :blog
  has_many :subscription_posts
  has_many :blog_post_category_assignments, dependent: :destroy
end
