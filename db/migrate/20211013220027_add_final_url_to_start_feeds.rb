class AddFinalUrlToStartFeeds < ActiveRecord::Migration[6.1]
  def change
    add_column :start_feeds, :final_url, :text, null: false
  end
end
