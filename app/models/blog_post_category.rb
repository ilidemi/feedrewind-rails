class BlogPostCategory < ApplicationRecord
  belongs_to :blog
  has_many :blog_post_category_assignments, foreign_key: :category_id, dependent: :destroy
end
