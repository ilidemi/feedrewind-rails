class CreateBlogPostLocks < ActiveRecord::Migration[6.1]
  def change
    create_table :blog_post_locks, id: false do |t|
      t.primary_key :blog_id, :bigint, null: false

      t.timestamps
      t.foreign_key :blogs
    end

    reversible do |dir|
      dir.up do
        Blog.all.each do |blog|
          BlogPostLock.create!(blog_id: blog.id)
        end
      end
    end
  end
end
