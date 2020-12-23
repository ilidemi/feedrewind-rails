class CreateCurrentRsses < ActiveRecord::Migration[6.1]
  def change
    create_table :current_rsses do |t|
      t.references :blog, null: false, foreign_key: true
      t.text :body

      t.timestamps
    end
  end
end
