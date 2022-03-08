class AddVersionToSubscriptions < ActiveRecord::Migration[6.1]
  def change
    add_column :subscriptions, :version, :integer

    reversible do |dir|
      dir.up do
        Subscription.with_discarded.each do |subscription|
          subscription.version = 1
          subscription.save!
        end
      end
    end

    change_column_null :subscriptions, :version, false
  end
end
