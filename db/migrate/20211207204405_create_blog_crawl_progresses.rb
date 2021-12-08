class CreateBlogCrawlProgresses < ActiveRecord::Migration[6.1]
  def change
    create_table :blog_crawl_progresses, id: false do |t|
      t.bigint :blog_id, null: false, options: "PRIMARY KEY"

      t.string :progress
      t.integer :count
      t.integer :epoch, null: false
      t.string :epoch_times

      t.timestamps
    end

    add_foreign_key :blog_crawl_progresses, :blogs
    execute "alter table blog_crawl_progresses add primary key (blog_id);"
  end
end
