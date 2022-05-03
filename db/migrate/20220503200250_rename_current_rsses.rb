class RenameCurrentRsses < ActiveRecord::Migration[6.1]
  def change
    rename_table :current_rsses, :subscription_rsses
  end
end
