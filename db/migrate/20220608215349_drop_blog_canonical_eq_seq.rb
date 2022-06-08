class DropBlogCanonicalEqSeq < ActiveRecord::Migration[6.1]
  def up
    execute "alter table blog_canonical_equality_configs alter column blog_id drop default"
    execute "drop sequence blog_canonical_equality_configs_blog_id_seq"
  end
end
