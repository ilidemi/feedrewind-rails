class AddPublishDateToSubscriptionPosts < ActiveRecord::Migration[6.1]
  def change
    add_column :subscription_posts, :published_at_local_date, :string, null: true

    reversible do |dir|
      dir.up do
        execute <<-SQL
          update subscription_posts
          set published_at_local_date = to_char(date_trunc('day', published_at at time zone 'UTC' at time zone 'PDT'), 'YYYY-MM-DD')
          where published_at is not null
        SQL
      end
    end
  end
end
