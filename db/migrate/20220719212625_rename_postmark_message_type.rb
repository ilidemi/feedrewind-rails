class RenamePostmarkMessageType < ActiveRecord::Migration[6.1]
  def change
    remove_column :postmark_messages, :type
    add_column :postmark_messages, :message_type, :postmark_message_type, null: false
  end
end
