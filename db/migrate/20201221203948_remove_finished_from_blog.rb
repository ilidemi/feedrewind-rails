class RemoveFinishedFromBlog < ActiveRecord::Migration[6.1]
  def change
    remove_column :blogs, :finished, :boolean
  end
end
