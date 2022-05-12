require "set"

class MakeUserIdsIntegers < ActiveRecord::Migration[6.1]
  def change
    # Add integer column to users
    add_column :users, :id_int, :bigint, null: true
    add_index :users, :id_int, unique: true

    # Add integer foreign key to user rsses, votes, subscriptions
    add_column :user_rsses, :user_id_int, :bigint, null: true
    add_column :subscriptions, :user_id_int, :bigint, null: true
    add_column :blog_crawl_votes, :user_id_int, :bigint, null: true

    # Populate integer keys everywhere
    used_ids = Set.new
    User.all.each do |user|
      new_id = SecureRandom.random_bytes(8).unpack("q").first & ((1 << 63) - 1)
      while used_ids.include?(new_id)
        new_id = SecureRandom.random_bytes(8).unpack("q").first & ((1 << 63) - 1)
      end
      user.update_attribute(:id_int, new_id)

      if user.user_rss
        user.user_rss.update_attribute(:user_id_int, new_id)
      else
        UserRss.create!(
          user_id: user.id,
          user_id_int: new_id,
          body: ""
        )
      end

      user.subscriptions.with_discarded.each do |subscription|
        subscription.update_attribute(:user_id_int, new_id)
      end

      user.blog_crawl_votes.each do |vote|
        vote.update_attribute(:user_id_int, new_id)
      end

      used_ids << new_id
    end
    puts used_ids
    change_column_null :users, :id_int, null: false
    change_column_null :user_rsses, :user_id_int, null: false
    # subscriptions and blog crawl votes can have null user

    # Add foreign key constraints with on update cascade
    add_foreign_key :user_rsses, :users, column: :user_id_int, primary_key: :id_int, on_update: :cascade
    add_foreign_key :subscriptions, :users, column: :user_id_int, primary_key: :id_int, on_update: :cascade
    add_foreign_key :blog_crawl_votes, :users, column: :user_id_int, primary_key: :id_int, on_update: :cascade

    # Separately:
    # Drop old foreign keys
    # Drop old id column
    # Rename id_int to id
    # Rename foreign key constraints
    # Migrate user jobs
  end
end
