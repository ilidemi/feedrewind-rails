class RemoveBouncedUsersForeignKey < ActiveRecord::Migration[6.1]
  def change
    remove_foreign_key :postmark_bounced_users, :users
  end
end
