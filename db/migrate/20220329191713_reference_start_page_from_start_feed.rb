class ReferenceStartPageFromStartFeed < ActiveRecord::Migration[6.1]
  def change
    add_reference :start_feeds, :start_page, null: true, foreign_key: true, type: :integer
  end
end
