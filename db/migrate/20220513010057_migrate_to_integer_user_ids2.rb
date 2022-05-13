class MigrateToIntegerUserIds2 < ActiveRecord::Migration[6.1]
  def change
    # Drop old columns
    remove_column :users, :id, :uuid
    remove_column :user_rsses, :user_id
    remove_column :subscriptions, :user_id
    remove_column :blog_crawl_votes, :user_id

    # Rename id_int to id
    rename_column :users, :id_int, :id
    rename_column :user_rsses, :user_id_int, :user_id
    rename_column :subscriptions, :user_id_int, :user_id
    rename_column :blog_crawl_votes, :user_id_int, :user_id
  end
end
