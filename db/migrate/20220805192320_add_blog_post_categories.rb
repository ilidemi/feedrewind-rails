class AddBlogPostCategories < ActiveRecord::Migration[6.1]
  def change
    create_table :blog_post_categories do |t|
      t.column :category, :text, null: false
      t.column :blog_post_id, :bigint, null: false
      t.foreign_key :blog_posts

      t.timestamps
    end

    create_table :blog_default_categories do |t|
      t.column :default_category, :text, null: false
      t.column :blog_id, :bigint, null: false
      t.foreign_key :blogs

      t.timestamps
    end
  end
end
