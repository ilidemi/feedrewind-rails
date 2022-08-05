class BlogTopCategories < ActiveRecord::Migration[6.1]
  def change
    drop_table :blog_default_categories
    create_table :blog_top_categories do |t|
      t.column :category, :text, null: false
      t.column :index, :integer, null: false
      t.column :blog_id, :bigint, null: false
      t.foreign_key :blogs

      t.timestamps
    end
  end
end
