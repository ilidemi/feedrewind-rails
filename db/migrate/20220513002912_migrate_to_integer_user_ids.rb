class MigrateToIntegerUserIds < ActiveRecord::Migration[6.1]
  def change
    # Drop old foreign keys
    change_table :user_rsses do |t|
      t.change_null(:user_id_int, false)
      t.remove_foreign_key(column: :user_id)
    end

    reversible do |dir|
      dir.up do
        execute "alter table user_rsses drop constraint user_rsses_pkey"
        execute "alter table user_rsses add primary key (user_id_int)"
      end
      dir.down do
        execute "alter table user_rsses drop constraint user_rsses_pkey"
        execute "alter table user_rsses add primary key (user_id)"
      end
    end

    change_table :subscriptions do |t|
      t.remove_foreign_key(column: :user_id)
    end

    change_table :blog_crawl_votes do |t|
      t.remove_foreign_key(column: :user_id)
    end

    # Migrate user jobs
    reversible do |dir|
      dir.up do
        User.all.each do |user|
          execute "update delayed_jobs set handler = replace(handler, '#{user.id}', '#{user.id_int}') where handler like '%#{user.id}%'"
        end
      end
      dir.down do
        User.all.each do |user|
          execute "update delayed_jobs set handler = replace(handler, '#{user.id_int}', '#{user.id}') where handler like '%#{user.id_int}%'"
        end
      end
    end

    # Use the new id
    reversible do |dir|
      dir.up do
        execute "alter table users drop constraint users_pkey"
        execute "alter table users add primary key (id_int)"
      end
      dir.down do
        execute "alter table users drop constraint users_pkey"
        execute "alter table users add primary key (id)"
      end
    end

    # Later:
    # Drop old column
    # Rename id_int to id
    # Rename foreign key constraints
  end
end
