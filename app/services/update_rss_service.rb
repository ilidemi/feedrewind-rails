require 'htmlentities'
require 'ox'

module UpdateRssService
  POSTS_IN_RSS = 15

  def UpdateRssService.init(subscription)
    welcome_item = generate_welcome_item(subscription)
    rss_document = generate_rss(subscription, [], [], welcome_item)
    rss_text = Ox.dump(rss_document)
    current_rss = CurrentRss.new(subscription_id: subscription.id, body: rss_text)
    current_rss.save!
  end

  def UpdateRssService.update_rss(subscription, to_publish_count)
    subscription_blog_posts = subscription
      .subscription_posts
      .includes(:blog_post)
    subscription_blog_posts_to_publish = subscription_blog_posts
      .where(is_published: false)
      .order("blog_posts.index asc")
      .limit(to_publish_count)
    blog_posts_to_publish = subscription_blog_posts_to_publish.map(&:blog_post)
    blog_posts_last_published = subscription_blog_posts
      .where(is_published: true)
      .order("blog_posts.index desc")
      .limit(POSTS_IN_RSS - blog_posts_to_publish.length)
      .map(&:blog_post)
      .reverse

    if blog_posts_to_publish.length + blog_posts_last_published.length < POSTS_IN_RSS
      welcome_item = generate_welcome_item(subscription)
    else
      welcome_item = nil
    end

    rss_document = generate_rss(subscription, blog_posts_to_publish, blog_posts_last_published, welcome_item)
    rss_text = Ox.dump(rss_document)

    CurrentRss.transaction do
      subscription_blog_posts_to_publish.each do |subscription_post|
        subscription_post.is_published = true
        subscription_post.save!
      end

      current_rss = CurrentRss.find_or_initialize_by(subscription_id: subscription.id)
      current_rss.body = rss_text
      current_rss.save!
    end
  end

  def self.generate_rss(subscription, blog_posts_to_publish, blog_posts_last_published, welcome_item)
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
    channel_title << "#{HTMLEntities.new.encode(subscription.name)} · Feeduler"
    channel << channel_title

    blog_posts_to_publish.to_enum.reverse_each do |blog_post|
      channel << generate_post_rss(subscription, blog_post)
    end

    blog_posts_last_published.to_enum.reverse_each do |blog_post|
      channel << generate_post_rss(subscription, blog_post)
    end

    if welcome_item
      channel << welcome_item
    end

    rss << channel
    document << rss
    document
  end

  def self.generate_post_rss(subscription, blog_post)
    item = Ox::Element.new("item")

    post_title = Ox::Element.new("title")
    post_title << HTMLEntities.new.encode(blog_post.title)
    item << post_title

    link = Ox::Element.new("link")
    link << HTMLEntities.new.encode(blog_post.url)
    item << link

    subscription_url = SubscriptionsHelper.subscription_url(subscription)
    description = Ox::Element.new("description")
    description << "<a href=\"#{subscription_url}\">Manage</a>"
    item << description

    item
  end

  def self.generate_welcome_item(subscription)
    item = Ox::Element.new("item")

    post_title = Ox::Element.new("title")
    post_title << "#{HTMLEntities.new.encode(subscription.name)} added to Feeduler"
    item << post_title

    subscription_url = SubscriptionsHelper.subscription_url(subscription)
    link = Ox::Element.new("link")
    link << subscription_url
    item << link

    description = Ox::Element.new("description")
    description << "<a href=\"#{subscription_url}\">Manage</a>"
    item << description

    item
  end

  private_class_method :generate_rss, :generate_post_rss
end