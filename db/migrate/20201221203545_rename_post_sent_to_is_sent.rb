class RenamePostSentToIsSent < ActiveRecord::Migration[6.1]
  def change
    rename_column :posts, :sent, :is_sent
  end
end
