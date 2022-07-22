class PostmarkBouncedUsers < ActiveRecord::Migration[6.1]
  def change
    create_table :postmark_bounced_users, id: false do |t|
      t.primary_key :user_id, :bigint, null: false
      t.foreign_key :users
      t.column :example_bounce_id, :bigint, null: false
      t.foreign_key :postmark_bounces, column: :example_bounce_id, primary_key: :id
      t.timestamps
    end
  end
end
