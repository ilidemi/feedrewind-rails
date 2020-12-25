class AddIsFetchedToBlog < ActiveRecord::Migration[6.1]
  def change
    add_column :blogs, :is_fetched, :boolean
  end
end
