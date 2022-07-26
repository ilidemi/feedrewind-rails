class SubscriptionRemovePauseVersion < ActiveRecord::Migration[6.1]
  def change
    remove_column :subscriptions, :pause_version
  end
end
