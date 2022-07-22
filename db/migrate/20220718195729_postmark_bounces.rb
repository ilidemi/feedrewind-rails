class PostmarkBounces < ActiveRecord::Migration[6.1]
  def change
    create_table :postmark_bounces, id: false do |t|
      t.primary_key :id, :bigint, null: false
      t.column :type, :text, null: false
      t.column :message_id, :text, null: true
      t.column :payload, :json, null: false
      t.timestamps
    end
  end
end
