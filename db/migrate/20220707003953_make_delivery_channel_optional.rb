class MakeDeliveryChannelOptional < ActiveRecord::Migration[6.1]
  def change
    change_column_null :user_settings, :delivery_channel, true
  end
end
