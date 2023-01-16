require 'securerandom'

class SupportAnonymousUsers < ActiveRecord::Migration[6.1]
  def change
    change_table :users do |t|
      change_column_null :users, :email, false
      change_column_null :users, :password_digest, false
      change_column_null :users, :auth_token, false
      t.uuid :product_user_id
      t.index :product_user_id, unique: true
    end

    reversible do |dir|
      dir.up do
        User.all.each do |user|
          user.update_attribute(:product_user_id, SecureRandom.uuid)
        end
      end
    end

    change_column_null :users, :product_user_id, false
  end
end
