class AddCategoryIdIndex < ActiveRecord::Migration[6.1]
  def change
    add_index :blog_post_category_assignments, :category_id
  end
end
