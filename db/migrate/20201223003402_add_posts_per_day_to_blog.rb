class AddPostsPerDayToBlog < ActiveRecord::Migration[6.1]
  def change
    add_column :blogs, :posts_per_day, :integer
  end
end
