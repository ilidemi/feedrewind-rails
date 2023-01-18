class AnonymizeTypedBlogUrls < ActiveRecord::Migration[6.1]
  def change
    remove_column :typed_blog_urls, :user_ip
    remove_column :typed_blog_urls, :user_agent
  end
end
