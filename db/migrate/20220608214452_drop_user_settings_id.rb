class DropUserSettingsId < ActiveRecord::Migration[6.1]
  def up
    remove_column :user_settings, :id
  end
end
