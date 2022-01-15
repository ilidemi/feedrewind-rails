class AddUpdateFailedToBlogStatus < ActiveRecord::Migration[6.1]
  def up
    execute "alter type blog_status add value 'update_from_feed_failed'"
  end
end
