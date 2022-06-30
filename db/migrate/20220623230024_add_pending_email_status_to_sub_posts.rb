class AddPendingEmailStatusToSubPosts < ActiveRecord::Migration[6.1]
  def up
    execute "alter type post_email_status add value 'pending'"
  end
end
