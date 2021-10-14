class AllowNullPostsPerDay < ActiveRecord::Migration[6.1]
  def change
    change_column_null :blogs, :posts_per_day, true
  end
end
