class RemoveIndexOnBlogName < ActiveRecord::Migration[6.1]
  def change
    remove_index :blogs, name: "index_blogs_on_name"
  end
end
