class CreateUserSettings < ActiveRecord::Migration[6.1]
  def change
    create_table :user_settings do |t|
      t.column :user_id, :bigint, null: false
      t.foreign_key :users

      t.column :timezone, :string, null: false

      t.timestamps
    end

    User.all.each do |user|
      UserSettings.create!(user_id: user.id, timezone: "America/Los_Angeles")
    end
  end
end
