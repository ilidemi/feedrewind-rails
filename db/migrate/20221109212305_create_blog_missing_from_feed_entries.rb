class CreateBlogMissingFromFeedEntries < ActiveRecord::Migration[6.1]
  def change
    create_table :blog_missing_from_feed_entries do |t|
      t.bigint :blog_id, null: false
      t.text :url, null: false

      t.foreign_key :blogs

      t.timestamps
    end
  end
end
