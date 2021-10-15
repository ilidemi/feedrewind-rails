class RemoveFetchStatusFromBlogs < ActiveRecord::Migration[6.1]
  def up
    remove_column :blogs, :fetch_status
    execute <<-SQL
    DROP TYPE blog_fetch_status;
    SQL
  end
end
