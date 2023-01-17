class TypedBlogUrls < ActiveRecord::Migration[6.1]
  def change
    create_table :typed_blog_urls do |t|
      t.text :typed_url, null: false
      t.text :stripped_url, null: false
      t.text :source, null: false
      t.text :result, null: false
      t.bigint :user_id
      t.text :user_ip, null: false
      t.text :user_agent

      t.timestamps
    end
  end
end
