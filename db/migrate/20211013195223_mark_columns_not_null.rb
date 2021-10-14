class MarkColumnsNotNull < ActiveRecord::Migration[6.1]
  def change
    change_column_null :start_feeds, :content, false
    change_column_null :start_feeds, :url, false
  end
end
