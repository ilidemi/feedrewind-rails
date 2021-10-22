class AddLooksWrongStatus < ActiveRecord::Migration[6.1]
  def up
    execute <<~SQL
      alter type blog_status add value 'crawled_looks_wrong';
    SQL
  end
end
