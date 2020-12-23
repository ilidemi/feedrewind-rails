class AddOrderToPosts < ActiveRecord::Migration[6.1]
  def change
    add_column :posts, :order, :int
  end
end
