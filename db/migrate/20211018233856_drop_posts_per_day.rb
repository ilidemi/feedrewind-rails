class DropPostsPerDay < ActiveRecord::Migration[6.1]
  def change
    remove_column :blogs, :posts_per_day
  end
end
