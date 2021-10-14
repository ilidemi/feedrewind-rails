class AddUrlToStartFeeds < ActiveRecord::Migration[6.1]
  def change
    add_column :start_feeds, :url, :text
  end
end
