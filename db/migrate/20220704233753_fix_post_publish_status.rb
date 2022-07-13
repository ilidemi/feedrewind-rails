class FixPostPublishStatus < ActiveRecord::Migration[6.1]
  def up
    execute "alter type post_publish_status add value 'email_sent'"
  end
end
