class ChangeIsPublishedToDate < ActiveRecord::Migration[6.1]
  def change
    add_column :subscription_posts, :published_at, :datetime, null: true

    reversible do |dir|
      dir.up do
        execute "update subscription_posts set published_at = '1970-01-01 00:00:00' where is_published = true"
      end
    end
  end
end
