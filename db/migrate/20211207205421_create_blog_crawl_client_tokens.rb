class CreateBlogCrawlClientTokens < ActiveRecord::Migration[6.1]
  def change
    create_table :blog_crawl_client_tokens, id: false do |t|
      t.bigint :blog_id, null: false

      t.string :value, null: false

      t.timestamps
    end

    add_foreign_key :blog_crawl_client_tokens, :blogs
    execute "alter table blog_crawl_client_tokens add primary key (blog_id);"
  end
end
