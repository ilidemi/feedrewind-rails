require 'ox'

module UpdateRssService
  POSTS_IN_RSS = 15

  def UpdateRssService.update_rss(blog_id)
    blog = Blog.find(blog_id)
    posts_to_publish = blog.posts
                           .where(is_published: false)
                           .order(order: :asc)
                           .limit(blog.posts_per_day)
    posts_last_published = blog.posts
                               .where(is_published: true)
                               .order(order: :desc)
                               .limit(POSTS_IN_RSS - posts_to_publish.length)
                               .reverse_order
    total_published_posts = blog.posts
                                .where(is_published: true)
                                .count
    total_posts = blog.posts.count

    rss_document = generate_rss(blog, posts_to_publish, posts_last_published, total_published_posts, total_posts)
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

  def self.generate_rss(blog, posts_to_publish, posts_last_published, total_published_posts, total_posts)
    document = Ox::Document.new

    instruct = Ox::Instruct.new(:xml)
    instruct[:version] = '1.0'
    instruct[:encoding] = 'UTF-8'
    document << instruct

    rss = Ox::Element.new('rss')
    rss[:version] = '2.0'

    channel = Ox::Element.new('channel')

    channel_title = Ox::Element.new('title')
    channel_title << "#{blog.name} - RSS Catchup"
    channel << channel_title

    posts_to_publish.to_enum.with_index.reverse_each do |post, post_index|
      post_number = total_published_posts + post_index + 1
      channel << generate_post_rss(post, post_number, total_posts)
    end

    posts_last_published.to_enum.with_index.reverse_each do |post, post_index|
      post_number = total_published_posts - posts_last_published.length + post_index + 1
      channel << generate_post_rss(post, post_number, total_posts)
    end

    rss << channel
    document << rss
    document
  end

  def self.generate_post_rss(post, post_number, total_posts)
    item = Ox::Element.new('item')

    post_title = Ox::Element.new('title')
    post_title << post.title
    item << post_title

    link = Ox::Element.new('link')
    link << post.link
    item << link

    description = Ox::Element.new('description')
    description << "#{post_number}/#{total_posts} - originally published on #{post.date}"
    item << description

    item
  end

  private_class_method :generate_rss, :generate_post_rss
end