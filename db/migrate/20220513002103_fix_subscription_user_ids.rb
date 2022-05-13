class FixSubscriptionUserIds < ActiveRecord::Migration[6.1]
  def change
    Subscription
      .with_discarded
      .where(user_id: nil)
      .each do |subscription|
      subscription.update_attribute(:user_id_int, nil)
    end

    User.all.each do |user|
      Subscription
        .with_discarded
        .where(user_id: user.id)
        .each do |subscription|
        subscription.update_attribute(:user_id_int, user.id_int)
      end
    end
  end
end
