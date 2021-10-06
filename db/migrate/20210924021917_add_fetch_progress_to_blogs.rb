class AddFetchProgressToBlogs < ActiveRecord::Migration[6.1]
  def change
    add_column :blogs, :fetch_progress, :string
  end
end
