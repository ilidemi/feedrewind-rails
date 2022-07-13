class DropEmailStatus < ActiveRecord::Migration[6.1]
  def up
    remove_column :subscription_posts, :email_status
    execute "drop type post_email_status"
  end
end
