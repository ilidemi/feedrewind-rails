class AddUpdateActionToBlogs < ActiveRecord::Migration[6.1]
  def change
    reversible do |dir|
      dir.up { execute "create type blog_update_action as enum ('recrawl', 'update_from_feed_or_fail', 'no_op', 'fail')" }
      dir.down { execute "drop type blog_update_action" }
    end

    add_column :blogs, :update_action, :blog_update_action

    reversible do |dir|
      dir.up do
        Blog.all.each do |blog|
          if blog.status == "manually_inserted"
            blog.update_action = "update_from_feed_or_fail"
          else
            blog.update_action = "recrawl"
          end

          blog.save!
        end
      end
    end

    change_column_null :blogs, :update_action, false
  end
end
