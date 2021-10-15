class AddCrawlFailed < ActiveRecord::Migration[6.1]
  def up
    execute <<-SQL
    alter type blog_status add value 'crawl_failed';
    SQL
  end
end
