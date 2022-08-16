class DropBlogPostCategories < ActiveRecord::Migration[6.1]
  def change
    drop_table :blog_top_categories
    drop_table :blog_post_categories
  end
end
