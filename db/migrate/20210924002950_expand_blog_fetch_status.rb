class ExpandBlogFetchStatus < ActiveRecord::Migration[6.1]
  def up
    execute <<-SQL
      create type blog_fetch_status as enum ('in_progress', 'succeeded', 'failed');
    SQL
    add_column :blogs, :fetch_status, :blog_fetch_status

    Blog.reset_column_information
    Blog.all.each do |blog|
      blog.update!(:fetch_status => 'succeeded')
    end
  end

  def down
    remove_column :blogs, :fetch_status

    execute <<-SQL
      drop type blog_fetch_status;
    SQL
  end
end
