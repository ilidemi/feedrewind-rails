require 'ox'

module UpdateRssService
  POSTS_IN_RSS = 30

  def UpdateRssService.update_rss(subscription, to_publish_count, now)
    subscription_blog_posts = subscription
      .subscription_posts
      .includes(:blog_post)
    subscription_posts_to_publish = subscription_blog_posts
      .where("published_at is null")
      .order("blog_posts.index asc")
      .limit(to_publish_count)
    subscription_blog_posts_unpublished_count = subscription_blog_posts
      .where("published_at is null")
      .length
    subscription_posts_last_published = subscription_blog_posts
      .where("published_at is not null")
      .order("blog_posts.index desc")
      .limit(POSTS_IN_RSS - subscription_posts_to_publish.length)
      .reverse

    subscription_posts_to_publish.each do |subscription_post|
      subscription_post.published_at = now.date
    end

    if subscription_posts_to_publish.length == subscription_blog_posts_unpublished_count
      subscription.final_item_published_at = now.date if subscription.final_item_published_at.nil?
      if subscription_posts_last_published.length + subscription_posts_to_publish.length == POSTS_IN_RSS
        subscription_posts_last_published = subscription_posts_last_published[1..]
      end
      final_item = generate_final_item(subscription)
    else
      final_item = nil
    end

    if subscription_posts_to_publish.length + subscription_posts_last_published.length + (final_item ? 1 : 0) < POSTS_IN_RSS
      welcome_item = generate_welcome_item(subscription)
    else
      welcome_item = nil
    end

    rss_document = generate_rss(
      subscription, subscription_posts_to_publish, subscription_posts_last_published, welcome_item, final_item
    )
    rss_text = Ox.dump(rss_document)

    SubscriptionRss.transaction do
      subscription.save!

      subscription_posts_to_publish.each do |subscription_post|
        subscription_post.save!
      end

      subscription_rss = SubscriptionRss.find_or_initialize_by(subscription_id: subscription.id)
      subscription_rss.body = rss_text
      subscription_rss.save!
    end
  end

  def self.generate_rss(
    subscription, subscription_posts_to_publish, subscription_posts_last_published, welcome_item, final_item
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
    channel_title << "#{subscription.name} · FeedRewind"
    channel << channel_title

    if final_item
      channel << final_item
    end

    subscription_posts_to_publish.to_enum.reverse_each do |subscription_post|
      channel << generate_post_rss(subscription, subscription_post)
    end

    subscription_posts_last_published.to_enum.reverse_each do |subscription_post|
      channel << generate_post_rss(subscription, subscription_post)
    end

    if welcome_item
      channel << welcome_item
    end

    rss << channel
    document << rss
    document
  end

  def self.generate_post_rss(subscription, subscription_post)
    item = Ox::Element.new("item")

    post_title = Ox::Element.new("title")
    post_title << subscription_post.blog_post.title
    item << post_title

    link = Ox::Element.new("link")
    link << subscription_post.blog_post.url
    item << link

    subscription_url = SubscriptionsHelper.subscription_url(subscription)
    description = Ox::Element.new("description")
    description << "<a href=\"#{subscription_url}\">Manage</a>"
    item << description

    pub_date = Ox::Element.new("pubDate")
    pub_date << subscription_post.published_at.to_formatted_s(:rfc822)
    item << pub_date

    item
  end

  def self.generate_welcome_item(subscription)
    item = Ox::Element.new("item")

    post_title = Ox::Element.new("title")
    post_title << "#{subscription.name} added to FeedRewind"
    item << post_title

    subscription_url = SubscriptionsHelper.subscription_url(subscription)
    link = Ox::Element.new("link")
    link << subscription_url
    item << link

    description = Ox::Element.new("description")
    description << "<a href=\"#{subscription_url}\">Manage</a>"
    item << description

    pub_date = Ox::Element.new("pubDate")
    pub_date << subscription.finished_setup_at.to_formatted_s(:rfc822)
    item << pub_date

    item
  end

  def self.generate_final_item(subscription)
    item = Ox::Element.new("item")

    post_title = Ox::Element.new("title")
    post_title << "You're all caught up with #{subscription.name}"
    item << post_title

    subscription_url = SubscriptionsHelper.subscription_url(subscription)
    link = Ox::Element.new("link")
    link << subscription_url
    item << link

    subscription_add_url = SubscriptionsHelper.subscription_add_url
    description = Ox::Element.new("description")
    description << "<a href=\"#{subscription_add_url}\">Read something else?</a>"
    item << description

    pub_date = Ox::Element.new("pubDate")
    pub_date << subscription.final_item_published_at.to_formatted_s(:rfc822)
    item << pub_date

    item
  end

  private_class_method :generate_rss, :generate_post_rss
end