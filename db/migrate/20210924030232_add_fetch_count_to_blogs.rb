class AddFetchCountToBlogs < ActiveRecord::Migration[6.1]
  def change
    add_column :blogs, :fetch_count, :integer
  end
end
