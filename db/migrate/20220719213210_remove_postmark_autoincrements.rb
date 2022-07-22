class RemovePostmarkAutoincrements < ActiveRecord::Migration[6.1]
  def up
    change_column_default :postmark_bounces, :id, nil
    change_column_default :postmark_bounced_users, :user_id, nil

    execute "drop sequence postmark_bounces_id_seq"
    execute "drop sequence postmark_bounced_users_user_id_seq"
  end
end
