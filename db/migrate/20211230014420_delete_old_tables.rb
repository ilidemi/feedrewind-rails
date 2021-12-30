class DeleteOldTables < ActiveRecord::Migration[6.1]
  def up
    remove_column :schedules, :old_blog_id
    remove_column :current_rsses, :old_blog_id
    remove_column :blog_crawl_client_tokens, :old_blog_id
    remove_column :blog_crawl_progresses, :old_blog_id

    drop_table :old_posts
    drop_table :old_blogs
  end
end
