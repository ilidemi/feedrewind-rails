class RenamePostmarkBounceType < ActiveRecord::Migration[6.1]
  def change
    rename_column :postmark_bounces, :type, :bounce_type
  end
end
