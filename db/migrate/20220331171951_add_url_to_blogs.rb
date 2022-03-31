class AddUrlToBlogs < ActiveRecord::Migration[6.1]
  def change
    add_column :blogs, :url, :string, null: true

    reversible do |dir|
      dir.up do
        Blog.all.each do |blog|
          blog.url = blog.feed_url
          blog.save!
        end
      end
    end
  end
end
