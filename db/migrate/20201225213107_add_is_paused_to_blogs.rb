class AddIsPausedToBlogs < ActiveRecord::Migration[6.1]
  def change
    add_column :blogs, :is_paused, :boolean
  end
end
