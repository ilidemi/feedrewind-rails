class PostmarkMessages < ActiveRecord::Migration[6.1]
  def change
    reversible do |dir|
      dir.up { execute "create type postmark_message_type as enum ('sub_initial', 'sub_final', 'sub_post')" }
      dir.down { execute "drop type postmark_message_type" }
    end

    create_table :postmark_messages, id: false do |t|
      t.primary_key :message_id, :text, null: false
      t.column :type, :postmark_message_type, null: false
      t.column :subscription_post_id, :bigint, null: true
      t.foreign_key :subscription_posts
      t.timestamps
    end
  end
end
