class AddTitleToStartFeeds < ActiveRecord::Migration[6.1]
  def change
    add_column :start_feeds, :title, :text, null: false
  end
end
