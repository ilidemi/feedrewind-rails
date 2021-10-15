class AddStatusToBlogs < ActiveRecord::Migration[6.1]
  def up
    execute <<-SQL
    CREATE TYPE blog_status AS ENUM ('crawl_in_progress', 'crawled', 'confirmed', 'live');
    SQL
    add_column :blogs, :status, :blog_status, null: false
  end

  def down
    remove_column :blogs, :status

    execute <<-SQL
    DROP TYPE blog_status;
    SQL
  end
end
