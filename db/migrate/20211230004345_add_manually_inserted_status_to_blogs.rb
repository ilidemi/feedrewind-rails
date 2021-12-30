class AddManuallyInsertedStatusToBlogs < ActiveRecord::Migration[6.1]
  def up
    execute "alter type blog_status add value 'manually_inserted'"
  end
end
