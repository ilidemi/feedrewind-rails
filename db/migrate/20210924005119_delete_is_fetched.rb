class DeleteIsFetched < ActiveRecord::Migration[6.1]
  def change
    remove_column :blogs, :is_fetched
    change_column_null :blogs, :fetch_status, false
  end
end
