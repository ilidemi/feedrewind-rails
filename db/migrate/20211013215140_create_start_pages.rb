class CreateStartPages < ActiveRecord::Migration[6.1]
  def change
    create_table :start_pages do |t|
      t.binary :content, null: false
      t.text :url, null: false

      t.timestamps
    end
  end
end
