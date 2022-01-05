class CreateCanonicalEqualityConfig < ActiveRecord::Migration[6.1]
  def change
    create_table :blog_canonical_equality_configs, id: false do |t|
      t.primary_key :blog_id, :bigint, null: false
      t.text :same_hosts, array: true, null: true
      t.boolean :expect_tumblr_paths, null: false

      t.timestamps
      t.foreign_key :blogs
    end

    reversible do |dir|
      dir.up do
        Blog.all.each do |blog|
          expect_tumblr_paths = blog.blog_posts.all? { |blog_post| /\/post\/\d+/.match?(blog_post.url) }
          
          BlogCanonicalEqualityConfig.create!(
            blog_id: blog.id,
            same_hosts: [],
            expect_tumblr_paths: expect_tumblr_paths
          )
        end
      end
    end
  end
end
