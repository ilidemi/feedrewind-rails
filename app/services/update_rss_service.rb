require "ox"

module UpdateRssService
  POSTS_IN_RSS = 15

  def UpdateRssService.init(blog)
    welcome_item = generate_welcome_item(blog)
    rss_document = generate_rss(blog, [], [], welcome_item, nil, nil)
    rss_text = Ox.dump(rss_document)
    current_rss = CurrentRss.new(blog_id: blog.id, body: rss_text)
    current_rss.save!
  end

  def UpdateRssService.update_rss(blog_id, to_publish_count)
    blog = Blog.find(blog_id)
    posts_to_publish = blog
      .posts
      .where(is_published: false)
      .order(order: :asc)
      .limit(to_publish_count)
    posts_last_published = blog
      .posts
      .where(is_published: true)
      .order(order: :desc)
      .limit(POSTS_IN_RSS - posts_to_publish.length)
      .reverse
    total_published_posts = blog
      .posts
      .where(is_published: true)
      .count
    total_posts = blog.posts.count

    if posts_to_publish.length + posts_last_published.length < POSTS_IN_RSS
      welcome_item = generate_welcome_item(blog)
    else
      welcome_item = nil
    end

    rss_document = generate_rss(
      blog, posts_to_publish, posts_last_published, welcome_item, total_published_posts, total_posts
    )
    rss_text = Ox.dump(rss_document)

    CurrentRss.transaction do
      posts_to_publish.each do |post|
        post.is_published = true
        post.save!
      end

      current_rss = CurrentRss.find_or_initialize_by(blog_id: blog.id)
      current_rss.body = rss_text
      current_rss.save!
    end
  end

  def self.generate_rss(
    blog, posts_to_publish, posts_last_published, welcome_item, total_published_posts, total_posts
  )
    document = Ox::Document.new

    instruct = Ox::Instruct.new(:xml)
    instruct[:version] = "1.0"
    instruct[:encoding] = "UTF-8"
    document << instruct

    rss = Ox::Element.new("rss")
    rss[:version] = "2.0"
    rss["xmlns:content"] = "http://purl.org/rss/1.0/modules/content/"

    channel = Ox::Element.new("channel")

    channel_title = Ox::Element.new("title")
    channel_title << "#{blog.name} · Feeduler"
    channel << channel_title

    posts_to_publish.to_enum.with_index.reverse_each do |post, post_index|
      post_number = total_published_posts + post_index + 1
      channel << generate_post_rss(post, post_number, total_posts)
    end

    posts_last_published.to_enum.with_index.reverse_each do |post, post_index|
      post_number = total_published_posts - posts_last_published.length + post_index + 1
      channel << generate_post_rss(post, post_number, total_posts)
    end

    if welcome_item
      channel << welcome_item
    end

    rss << channel
    document << rss
    document
  end

  def self.generate_post_rss(post, post_number, total_posts)
    item = Ox::Element.new("item")

    post_title = Ox::Element.new("title")
    post_title << post.title
    item << post_title

    link = Ox::Element.new("link")
    link << post.link
    item << link

    description = Ox::Element.new("description")
    description << "#{post_number}/#{total_posts} - originally published on #{post.date}"
    item << description

    item
  end

  def self.generate_welcome_item(blog)
    item = Ox::Element.new("item")

    post_title = Ox::Element.new("title")
    post_title << "#{blog.name} added to Feeduler"
    item << post_title

    blog_path = BlogsHelper.blog_path(blog)
    link = Ox::Element.new("link")
    link << blog_path
    item << link

    description = Ox::Element.new("content:encoded")
    description << "<![CDATA[<a href=\"#{blog_path}\">Manage</a>]]>"
    item << description

    item
  end

  private_class_method :generate_rss, :generate_post_rss
end