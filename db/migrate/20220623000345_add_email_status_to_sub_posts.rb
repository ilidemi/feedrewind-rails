class AddEmailStatusToSubPosts < ActiveRecord::Migration[6.1]
  def change
    reversible do |dir|
      dir.up { execute "create type post_email_status as enum ('sent', 'skipped')" }
      dir.down { execute "drop type post_email_status" }
    end

    add_column :subscription_posts, :email_status, :post_email_status

    reversible do |dir|
      dir.up do
        execute "update subscription_posts set email_status = 'skipped' where published_at_local_date is not null"
      end
    end
  end
end
