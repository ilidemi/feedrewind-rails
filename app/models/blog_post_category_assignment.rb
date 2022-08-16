class BlogPostCategoryAssignment < ApplicationRecord
  belongs_to :blog_post
  belongs_to :blog_post_category, foreign_key: :category_id
end
