class AddFinalUrlToStartPages < ActiveRecord::Migration[6.1]
  def change
    add_column :start_pages, :final_url, :text, null: false
  end
end
