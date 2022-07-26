class SubscriptionSeparatePauseVersion < ActiveRecord::Migration[6.1]
  def change
    add_column :subscriptions, :schedule_version, :integer
    add_column :subscriptions, :pause_version, :integer
    Subscription.with_discarded.each do |subscription|
      subscription.schedule_version = subscription.version
      subscription.pause_version = 1
      subscription.save!
    end

    change_column_null :subscriptions, :schedule_version, false
    change_column_null :subscriptions, :pause_version, false
    remove_column :subscriptions, :version
  end
end
