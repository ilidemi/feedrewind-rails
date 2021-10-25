class DropArticles < ActiveRecord::Migration[6.1]
  def up
    drop_table :articles
  end
end
