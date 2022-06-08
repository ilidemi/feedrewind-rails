class DropUnusedSequences < ActiveRecord::Migration[6.1]
  def up
    execute "alter table blogs alter column id drop default"
    execute "drop sequence blogs_id_seq"

    execute "alter table last_time_travels alter column id drop default"
    execute "drop sequence last_time_travels_id_seq"

    execute "alter table start_feeds alter column id drop default"
    execute "drop sequence start_feeds_id_seq"

    execute "alter table subscriptions alter column id drop default"
    execute "drop sequence subscriptions_id_seq"
  end
end
