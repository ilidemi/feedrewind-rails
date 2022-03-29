class MakeStartFeedFieldsOptional < ActiveRecord::Migration[6.1]
  def change
    change_column_null :start_feeds, :final_url, true
    change_column_null :start_feeds, :content, true
  end
end
