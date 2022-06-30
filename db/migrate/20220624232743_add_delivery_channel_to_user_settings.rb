class AddDeliveryChannelToUserSettings < ActiveRecord::Migration[6.1]
  def change
    reversible do |dir|
      dir.up { execute "create type post_delivery_channel as enum ('single_feed', 'multiple_feeds', 'email')" }
      dir.down { execute "drop type post_delivery_channel" }
    end

    add_column :user_settings, :delivery_channel, :post_delivery_channel
    UserSettings.all.each do |user_settings|
      user_settings.delivery_channel = "multiple_feeds"
      user_settings.save!
    end
    change_column_null :user_settings, :delivery_channel, false
  end
end
