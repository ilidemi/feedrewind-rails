class CreatePosts < ActiveRecord::Migration[6.1]
  def change
    create_table :posts do |t|
      t.references :blog, null: false, foreign_key: true
      t.string :link
      t.string :title
      t.string :date
      t.boolean :sent

      t.timestamps
    end
  end
end
