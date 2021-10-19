class AddIsAddedPastMidnightToBlogs < ActiveRecord::Migration[6.1]
  def change
    add_column :blogs, :is_added_past_midnight, :boolean, null: false
  end
end
