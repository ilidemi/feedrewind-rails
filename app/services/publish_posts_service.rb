require 'digest'
require 'ox'
require 'set'

module PublishPostsService
  POSTS_IN_RSS = 30

  def PublishPostsService.init_subscription(
    subscription, should_publish_rss_posts, utc_now, local_date, local_date_str
  )
    User.transaction do
      user = subscription.user
      subscriptions = user
        .subscriptions
        .where(status: "live")
        .order("finished_setup_at desc, id desc")
        .to_a

      case user.user_settings.delivery_channel
      when "single_feed", "multiple_feeds"
        new_posts_by_sub_id = {}
        subscription_blog_posts_by_sub_id = subscriptions.to_h do |sub|
          [
            sub.id,
            sub.subscription_posts.includes(:blog_post)
          ]
        end

        if should_publish_rss_posts
          schedule = subscription.schedules.find_by(day_of_week: ScheduleHelper::day_of_week(local_date))
          new_posts = subscription_blog_posts_by_sub_id[subscription.id]
            .where(published_at: nil)
            .order("blog_posts.index asc")
            .limit(schedule.count)
            .to_a

          new_posts.each do |subscription_post|
            subscription_post.published_at = utc_now
            subscription_post.published_at_local_date = local_date_str
          end

          Rails.logger.info("Subscription #{subscription.id}: will publish #{new_posts.length} new posts")
          new_posts_by_sub_id[subscription.id] = new_posts

          if subscription.final_item_published_at.nil? &&
            subscription.subscription_posts.where(published_at: nil).length == new_posts.length

            subscription.final_item_published_at = utc_now
            Rails.logger.info("Will publish the final item for subscription #{subscription.id}")
          end
        else
          new_posts = []
        end

        self.publish_rss_feeds(user, subscriptions, new_posts_by_sub_id, subscription_blog_posts_by_sub_id)
        publish_status = "rss_published"

        new_posts.each do |subscription_post|
          subscription_post.save!
        end
      when "email"
        # The job won't be visible until the transaction is committed
        EmailInitialItemJob.perform_later(user.id, subscription.id, ScheduleHelper::utc_str(utc_now))

        publish_status = "email_pending"
      else
        raise "Unknown delivery channel: #{user.user_settings.delivery_channel}"
      end

      subscription.initial_item_publish_status = publish_status
      subscription.save!
    end
  end

  def PublishPostsService.publish_for_user(user_id, utc_now, local_date, local_date_str, scheduled_for_str)
    User.transaction do
      user = User.find(user_id)
      subscriptions = user
        .subscriptions
        .where(status: "live")
        .order("finished_setup_at desc, id desc")
        .to_a
      Rails.logger.info("#{subscriptions.length} subscriptions")

      new_posts_by_sub_id = {}
      final_item_subs = []
      subscription_blog_posts_by_sub_id = {}
      subscriptions.each do |subscription|
        subscription_blog_posts = subscription.subscription_posts.includes(:blog_post)
        subscription_blog_posts_by_sub_id[subscription.id] = subscription_blog_posts

        if !subscription.is_paused
          schedule = subscription.schedules.find_by(day_of_week: ScheduleHelper::day_of_week(local_date))
          new_posts = subscription_blog_posts
            .where(published_at: nil)
            .order("blog_posts.index asc")
            .limit(schedule.count)
            .to_a

          new_posts.each do |subscription_post|
            subscription_post.published_at = utc_now
            subscription_post.published_at_local_date = local_date_str
          end

          Rails.logger.info("Subscription #{subscription.id}: will publish #{new_posts.length} new posts")
        else
          new_posts = []
          Rails.logger.info("Skipping subscription #{subscription.id}")
        end
        new_posts_by_sub_id[subscription.id] = new_posts

        if subscription.final_item_published_at.nil? &&
          subscription.subscription_posts.where(published_at: nil).length == new_posts.length

          subscription.final_item_published_at = utc_now
          final_item_subs << subscription
          Rails.logger.info("Will publish the final item for subscription #{subscription.id}")

          ProductEvent.create!(
            product_user_id: user.product_user_id,
            event_type: "finish subscription",
            event_properties: {
              subscription_id: subscription.id,
              blog_url: subscription.blog.best_url
            }
          )
        end
      end

      case user.user_settings.delivery_channel
      when "single_feed", "multiple_feeds"
        self.publish_rss_feeds(user, subscriptions, new_posts_by_sub_id, subscription_blog_posts_by_sub_id)
        publish_status = "rss_published"
      when "email"
        unless new_posts_by_sub_id.empty?
          # The job won't be visible until the transaction is committed
          EmailPostsJob.perform_later(user.id, local_date_str, scheduled_for_str, final_item_subs.map(&:id))
        end

        publish_status = "email_pending"
      else
        raise "Unknown delivery channel: #{user.user_settings.delivery_channel}"
      end

      new_posts_by_sub_id.values.each do |subscription_posts|
        subscription_posts.each do |subscription_post|
          subscription_post.publish_status = publish_status
          subscription_post.save!
        end
      end
      final_item_subs.each do |subscription|
        subscription.final_item_publish_status = publish_status
        subscription.save!
      end
    end
  end

  def self.publish_rss_feeds(user, subscriptions, new_posts_by_sub_id, subscription_blog_posts_by_sub_id)
    sha256 = Digest::SHA256.new
    user_dates_items = []
    subscriptions.each do |subscription|
      Rails.logger.info("Generating RSS for subscription #{subscription.id}")
      new_posts = new_posts_by_sub_id[subscription.id] || []
      subscription_blog_posts = subscription_blog_posts_by_sub_id[subscription.id]
      remaining_posts_count = POSTS_IN_RSS - (subscription.final_item_published_at ? 1 : 0) - new_posts.length
      remaining_posts = subscription_blog_posts
        .where("published_at is not null")
        .order("blog_posts.index desc")
        .limit(remaining_posts_count)
        .reverse
        .to_a

      subscription_url = SubscriptionsHelper::subscription_url(subscription)
      subscription_items = []
      if subscription.final_item_published_at
        Rails.logger.info("Generating final item")
        final_item = generate_rss_item(
          title: "You're all caught up with #{subscription.name}",
          url: subscription_url,
          guid: sha256.hexdigest("#{subscription.id}-final"),
          description: "<a href=\"#{SubscriptionsHelper.subscription_add_url}\">Want to read something else?</a>",
          pub_date: subscription.final_item_published_at
        )
        subscription_items << final_item
        user_dates_items << [subscription.final_item_published_at, final_item]
      end

      subscription_posts = remaining_posts + new_posts
      subscription_posts.reverse_each do |subscription_post|
        guid = sha256.hexdigest(subscription_post.id.to_s)
        subscription_item = generate_rss_item(
          title: subscription_post.blog_post.title,
          url: SubscriptionsHelper.post_url(subscription_post),
          guid: guid,
          description: "<a href=\"#{subscription_url}\">Manage</a>",
          pub_date: subscription_post.published_at
        )
        subscription_items << subscription_item

        user_item = generate_rss_item(
          title: subscription_post.blog_post.title,
          url: SubscriptionsHelper.post_url(subscription_post),
          guid: guid,
          description: "from #{subscription.name}<br><br><a href=\"#{subscription_url}\">Manage</a>",
          pub_date: subscription_post.published_at
        )
        user_dates_items << [subscription_post.published_at, user_item]
      end

      if subscription_items.length < POSTS_IN_RSS
        Rails.logger.info("Generating initial item")
        initial_item = generate_rss_item(
          title: "#{subscription.name} added to FeedRewind",
          url: subscription_url,
          guid: sha256.hexdigest("#{subscription.id}-welcome"),
          description: "<a href=\"#{subscription_url}\">Manage</a>",
          pub_date: subscription.finished_setup_at
        )
        subscription_items << initial_item
        user_dates_items << [subscription.finished_setup_at, initial_item]
      end

      subscription_rss_text = generate_rss(
        title: "#{subscription.name} · FeedRewind",
        url: subscription_url,
        items: subscription_items
      )
      Rails.logger.info("Total subscription items: #{subscription_items.length}")

      subscription_rss = SubscriptionRss.find_or_initialize_by(subscription_id: subscription.id)
      subscription_rss.body = subscription_rss_text
      subscription_rss.save!
      Rails.logger.info("Saved subscription RSS")
    end

    merged_user_items = user_dates_items
      .sort_by.with_index do |date_item, index|
      # Stable sort by date asc, index desc
      [date_item.first, -index]
    end
      .reverse # Date desc, index asc (= publish date desc, sub date desc, post index desc)
      .map(&:second)
      .take(POSTS_IN_RSS)

    new_user_items_count = new_posts_by_sub_id.values.map(&:length).sum
    Rails.logger.info("Total user items: #{merged_user_items.length} (#{new_user_items_count} new)")
    user_rss_text = generate_rss(
      title: "FeedRewind",
      url: "https://feedrewind.com",
      items: merged_user_items
    )

    user_rss = UserRss.find_or_initialize_by(user_id: user.id)
    user_rss.body = user_rss_text
    user_rss.save!
    Rails.logger.info("Saved user RSS")
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

  private_class_method :generate_rss, :generate_rss_item
end
