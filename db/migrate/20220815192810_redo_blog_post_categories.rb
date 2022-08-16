class RedoBlogPostCategories < ActiveRecord::Migration[6.1]
  def change
    create_table :blog_post_categories do |t|
      t.column :blog_id, :bigint, null: false
      t.foreign_key :blogs

      t.column :name, :text, null: false
      t.column :index, :integer, null: false
      t.column :is_top, :boolean, null: false

      t.timestamps
    end

    create_table :blog_post_category_assignments do |t|
      t.column :blog_post_id, :bigint, null: false
      t.foreign_key :blog_posts

      t.column :category_id, :bigint, null: false
      t.foreign_key :blog_post_categories, column: :category_id

      t.timestamps
    end
  end
end
