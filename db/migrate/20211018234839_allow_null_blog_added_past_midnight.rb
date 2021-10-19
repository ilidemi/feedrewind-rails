class AllowNullBlogAddedPastMidnight < ActiveRecord::Migration[6.1]
  def change
    change_column_null :blogs, :is_added_past_midnight, true
  end
end
