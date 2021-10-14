class CreateStartFeeds < ActiveRecord::Migration[6.1]
  def change
    create_table :start_feeds do |t|
      t.binary :content

      t.timestamps
    end
  end
end
