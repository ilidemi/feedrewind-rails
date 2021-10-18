class AddFetchProgressEpochToBlogs < ActiveRecord::Migration[6.1]
  def change
    remove_column :blogs, :fetch_epoch
    add_column :blogs, :fetch_progress_epoch, :integer, null: false
    add_column :blogs, :fetch_count_epoch, :integer, null: false
  end
end
