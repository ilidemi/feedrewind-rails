class AddLooksWrongToBlogs < ActiveRecord::Migration[6.1]
  def change
    add_column :blogs, :looks_wrong, :boolean
  end
end
