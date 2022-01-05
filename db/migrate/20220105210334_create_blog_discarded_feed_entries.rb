class CreateBlogDiscardedFeedEntries < ActiveRecord::Migration[6.1]
  def change
    create_table :blog_discarded_feed_entries do |t|
      t.bigint :blog_id, null: false
      t.string :url, null: false

      t.timestamps
      t.foreign_key :blogs
    end
  end
end
