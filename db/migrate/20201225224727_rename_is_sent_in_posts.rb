class RenameIsSentInPosts < ActiveRecord::Migration[6.1]
  def change
    rename_column :posts, :is_sent, :is_published
  end
end
