class UserIdPkeyInUserSettings < ActiveRecord::Migration[6.1]
  def up
    execute "alter table user_settings drop constraint user_settings_pkey"
    execute "alter table user_settings add primary key (user_id)"
  end

  def down
    execute "alter table user_settings drop constraint user_settings_pkey"
    execute "alter table user_settings add primary key (id)"
  end
end
