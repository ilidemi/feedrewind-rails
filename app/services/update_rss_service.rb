require 'ox'

module UpdateRssService
  POSTS_IN_RSS = 15

  def UpdateRssService.update_rss(blog_id)
    blog = Blog.find(blog_id)
    posts_to_send = blog.posts
                        .where(is_sent: false)
                        .order(order: :asc)
                        .limit(blog.posts_per_day)
    posts_last_sent = blog.posts
                          .where(is_sent: true)
                          .order(order: :desc)
                          .limit(POSTS_IN_RSS - posts_to_send.length)
                          .reverse_order
    total_sent_posts = blog.posts
                           .where(is_sent: true)
                           .count
    total_posts = blog.posts.count

    rss_document = generate_rss(blog, posts_to_send, posts_last_sent, total_sent_posts, total_posts)
    rss_text = Ox.dump(rss_document)

    CurrentRss.transaction do
      posts_to_send.each do |post|
        post.is_sent = true
        post.save!
      end

      current_rss = CurrentRss.find_or_initialize_by(blog_id: blog.id)
      current_rss.body = rss_text
      current_rss.save!
    end
  end

  def self.generate_rss(blog, posts_to_send, posts_last_sent, total_sent_posts, total_posts)
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

    posts_to_send.to_enum.with_index.reverse_each do |post, post_index|
      post_number = total_sent_posts + post_index + 1
      channel << generate_post_rss(post, post_number, total_posts)
    end

    posts_last_sent.to_enum.with_index.reverse_each do |post, post_index|
      post_number = total_sent_posts - posts_last_sent.length + post_index + 1
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