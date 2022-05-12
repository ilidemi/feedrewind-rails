class AddUserRss < ActiveRecord::Migration[6.1]
  def change
    create_table :user_rsses, id: false do |t|
      t.primary_key :user_id, :uuid, null: false
      t.foreign_key :users
      t.column :body, :text, null: false

      t.timestamps
    end
  end
end
