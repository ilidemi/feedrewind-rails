class DropIntegerIdFromUsers < ActiveRecord::Migration[6.1]
  def change
    remove_column :users, :integer_id
  end
end
