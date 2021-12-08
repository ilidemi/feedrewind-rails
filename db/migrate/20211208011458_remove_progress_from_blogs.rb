class RemoveProgressFromBlogs < ActiveRecord::Migration[6.1]
  def change
    remove_column :blogs, :fetch_progress
    remove_column :blogs, :fetch_count
    remove_column :blogs, :fetch_progress_epoch
    remove_column :blogs, :fetch_count_epoch
  end
end
