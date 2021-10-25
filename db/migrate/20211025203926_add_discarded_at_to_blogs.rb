class AddDiscardedAtToBlogs < ActiveRecord::Migration[6.1]
  def change
    add_column :blogs, :discarded_at, :datetime
  end
end
