class AddFetchEpochToBlogs < ActiveRecord::Migration[6.1]
  def change
    add_column :blogs, :fetch_epoch, :integer, null: false
  end
end
