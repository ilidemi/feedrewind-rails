require 'digest'
require 'ox'

module UpdateRssServiceNew
  POSTS_IN_RSS = 30

  def UpdateRssServiceNew.init_subscription(subscription, should_publish_posts, now)
    update(subscription.user_id, now, should_publish_posts ? subscription.id : :none)
  end

  def UpdateRssServiceNew.update_for_user(user_id, now)
    update(user_id, now, :all)
  end

  def UpdateRssServiceNew.update(user_id, now, publish_posts_for)
    sha256 = Digest::SHA256.new

    User.transaction do
      user = User.find(user_id)
      subscriptions = user
        .subscriptions
        .where(status: "live")
        .order("finished_setup_at desc, id desc")
      Rails.logger.info("#{subscriptions.length} subscriptions")
      user_dates_items = []
      new_user_items_count = 0

      subscriptions.each do |subscription|
        Rails.logger.info("Subscription #{subscription.id}")
        schedule = subscription.schedules.find_by(day_of_week: now.day_of_week)
        subscription_blog_posts = subscription
          .subscription_posts
          .includes(:blog_post)
        if !subscription.is_paused && [subscription.id, :all].include?(publish_posts_for)
          subscription_posts_to_publish = subscription_blog_posts
            .where("published_at is null")
            .order("blog_posts.index asc")
            .limit(schedule.count)
            .to_a
        else
          subscription_posts_to_publish = []
        end
        subscription_blog_posts_unpublished_count = subscription_blog_posts
          .where("published_at is null")
          .length
        subscription_posts_last_published = subscription_blog_posts
          .where("published_at is not null")
          .order("blog_posts.index desc")
          .limit(POSTS_IN_RSS - subscription_posts_to_publish.length)
          .reverse
          .to_a

        Rails.logger.info("Published: #{subscription_posts_last_published.length}, to publish: #{subscription_posts_to_publish.length}")
        new_user_items_count += subscription_posts_to_publish.length

        subscription_posts_to_publish.each do |subscription_post|
          subscription_post.published_at = now.date
        end
        subscription_posts = subscription_posts_last_published + subscription_posts_to_publish

        subscription_url = SubscriptionsHelper.subscription_url(subscription)
        subscription_dates_items = []

        if subscription_posts_to_publish.length == subscription_blog_posts_unpublished_count
          Rails.logger.info("Publishing final item")
          subscription.final_item_published_at = now.date if subscription.final_item_published_at.nil?
          subscription_add_url = SubscriptionsHelper.subscription_add_url
          final_item = generate_rss_item(
            title: "You're all caught up with #{subscription.name}",
            url: subscription_url,
            guid: sha256.hexdigest("#{subscription.id}-final"),
            description: "<a href=\"#{subscription_add_url}\">Read something else?</a>",
            pub_date: subscription.final_item_published_at
          )
          subscription_dates_items << [subscription.final_item_published_at, final_item]
          user_dates_items << [subscription.final_item_published_at, final_item]
        end

        subscription_posts.reverse_each do |subscription_post|
          break if subscription_dates_items.length == POSTS_IN_RSS

          guid = sha256.hexdigest(subscription_post.id.to_s)
          subscription_item = generate_rss_item(
            title: subscription_post.blog_post.title,
            url: subscription_post.blog_post.url,
            guid: guid,
            description: "<a href=\"#{subscription_url}\">Manage</a>",
            pub_date: subscription_post.published_at
          )
          subscription_dates_items << [subscription_post.published_at, subscription_item]

          user_item = generate_rss_item(
            title: subscription_post.blog_post.title,
            url: subscription_post.blog_post.url,
            guid: guid,
            description: "from #{subscription.name}<br><br><a href=\"#{subscription_url}\">Manage</a>",
            pub_date: subscription_post.published_at
          )
          user_dates_items << [subscription_post.published_at, user_item]
        end

        if subscription_dates_items.length < POSTS_IN_RSS
          Rails.logger.info("Publishing welcome item")
          welcome_item = generate_rss_item(
            title: "#{subscription.name} added to FeedRewind",
            url: subscription_url,
            guid: sha256.hexdigest("#{subscription.id}-welcome"),
            description: "<a href=\"#{subscription_url}\">Manage</a>",
            pub_date: subscription.finished_setup_at
          )
          subscription_dates_items << [subscription.finished_setup_at, welcome_item]
          user_dates_items << [subscription.finished_setup_at, welcome_item]
        end

        subscription_items = subscription_dates_items.map(&:second)
        subscription_rss_text = generate_rss(
          title: "#{subscription.name} · FeedRewind",
          url: subscription_url,
          items: subscription_items
        )
        Rails.logger.info("Total subscription items: #{subscription_items.length}")

        subscription.save!
        subscription_posts_to_publish.each do |subscription_post|
          subscription_post.save!
        end

        subscription_rss = SubscriptionRss.find_or_initialize_by(subscription_id: subscription.id)
        subscription_rss.body = subscription_rss_text
        subscription_rss.save!
      end

      merged_user_items = user_dates_items
        .sort_by.with_index do |date_item, index|
        # Stable sort by date asc, index desc
        [date_item.first, -index]
      end
        .reverse # Date desc, index asc (= publish date desc, sub date desc, post index desc)
        .map(&:second)
        .take(POSTS_IN_RSS)

      Rails.logger.info("Total user items: #{merged_user_items.length} (#{new_user_items_count} new)")
      user_rss_text = generate_rss(
        title: "FeedRewind",
        url: "https://feedrewind.herokuapp.com",
        items: merged_user_items
      )

      user_rss = UserRss.find_or_initialize_by(user_id: user_id)
      user_rss.body = user_rss_text
      user_rss.save!
    end
  end

  def self.generate_rss(title:, url:, items:)
    document = Ox::Document.new

    instruct = Ox::Instruct.new(:xml)
    instruct[:version] = "1.0"
    instruct[:encoding] = "UTF-8"
    document << instruct

    rss = Ox::Element.new("rss")
    rss[:version] = "2.0"
    #noinspection HttpUrlsUsage
    rss["xmlns:content"] = "http://purl.org/rss/1.0/modules/content/"

    channel = Ox::Element.new("channel")

    title_xml = Ox::Element.new("title")
    title_xml << title
    channel << title_xml

    link_xml = Ox::Element.new("link")
    link_xml << url
    channel << link_xml

    items.each do |item|
      channel << item
    end

    rss << channel
    document << rss

    Ox.dump(document)
  end

  def self.generate_rss_item(title:, url:, guid:, description:, pub_date:)
    item = Ox::Element.new("item")

    title_xml = Ox::Element.new("title")
    title_xml << title
    item << title_xml

    link_xml = Ox::Element.new("link")
    link_xml << url
    item << link_xml

    guid_xml = Ox::Element.new("guid")
    guid_xml["isPermaLink"] = false
    guid_xml << guid
    item << guid_xml

    description_xml = Ox::Element.new("description")
    description_xml << description
    item << description_xml

    pub_date_xml = Ox::Element.new("pubDate")
    pub_date_xml << pub_date.to_formatted_s(:rfc822)
    item << pub_date_xml

    item
  end

  private_class_method :update, :generate_rss, :generate_rss_item
end
