class AddFinishedSetupAtToSubscriptions < ActiveRecord::Migration[6.1]
  def change
    add_column :subscriptions, :finished_setup_at, :datetime, null: true

    Subscription.with_discarded.each do |subscription|
      if subscription.status == "live"
        subscription.finished_setup_at = subscription.created_at
        subscription.save!
      end
    end
  end
end
