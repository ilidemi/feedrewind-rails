class DropBlogLockSeq < ActiveRecord::Migration[6.1]
  def up
    execute "alter table blog_post_locks alter column blog_id drop default"
    execute "drop sequence blog_post_locks_blog_id_seq"
  end
end
