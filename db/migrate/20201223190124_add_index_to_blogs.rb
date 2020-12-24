class AddIndexToBlogs < ActiveRecord::Migration[6.1]
  def change
    add_index :blogs, :name, unique: true
  end
end
