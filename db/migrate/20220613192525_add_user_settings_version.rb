class AddUserSettingsVersion < ActiveRecord::Migration[6.1]
  def change
    add_column :user_settings, :version, :integer
    UserSettings.all.each do |s|
      s.update_attribute(:version, 1)
    end
    change_column_null :user_settings, :version, false
  end
end
