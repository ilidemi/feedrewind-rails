class AddEverythingCategory < ActiveRecord::Migration[6.1]
  def up
    Blog.all.each do |blog|
      next unless blog.blog_post_categories.empty?

      everything = BlogPostCategory.create!(
        blog_id: blog.id,
        name: "Everything",
        index: 0,
        is_top: true
      )

      blog.blog_posts.each do |blog_post|
        BlogPostCategoryAssignment.create!(
          blog_post_id: blog_post.id,
          category_id: everything.id
        )
      end
    end
  end
end
