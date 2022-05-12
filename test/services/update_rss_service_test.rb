require "test_helper"

#noinspection HttpUrlsUsage
class UpdateRssServiceTest < ActiveSupport::TestCase
  test "init" do
    subscription = subscriptions(:test)
    blog = blogs(:test)
    (1..5).each do |index|
      blog.blog_posts.create!(
        id: index,
        blog_id: blog.id,
        index: index,
        url: "https://blog/#{index}",
        title: "Post #{index}"
      )

      subscription.subscription_posts.create!(
        id: index,
        blog_post_id: index,
        subscription_id: subscription.id,
        published_at: nil
      )
    end

    now = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-06 00:00:00"))
    UpdateRssService.update_rss(subscription, 0, now)
    actual_body = SubscriptionRss.find_by(subscription_id: subscription.id).body
    expected_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription · FeedRewind</title>
    <item>
      <title>Test Subscription added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal actual_body, expected_body
  end

  test "welcome + 1" do
    subscription = subscriptions(:test)
    blog = blogs(:test)
    (1..5).each do |index|
      blog.blog_posts.create!(
        id: index,
        blog_id: blog.id,
        index: index,
        url: "https://blog/#{index}",
        title: "Post #{index}"
      )

      subscription.subscription_posts.create!(
        id: index,
        blog_post_id: index,
        subscription_id: subscription.id,
        published_at: nil
      )
    end

    now = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-06 00:00:00"))
    UpdateRssService.update_rss(subscription, 1, now)
    actual_body = SubscriptionRss.find_by(subscription_id: subscription.id).body
    expected_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription · FeedRewind</title>
    <item>
      <title>Post 1</title>
      <link>https://blog/1</link>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Test Subscription added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal actual_body, expected_body
  end

  test "welcome + multiple" do
    subscription = subscriptions(:test)
    blog = blogs(:test)
    (1..5).each do |index|
      blog.blog_posts.create!(
        id: index,
        blog_id: blog.id,
        index: index,
        url: "https://blog/#{index}",
        title: "Post #{index}"
      )

      subscription.subscription_posts.create!(
        id: index,
        blog_post_id: index,
        subscription_id: subscription.id,
        published_at: nil
      )
    end

    now = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-06 00:00:00"))
    UpdateRssService.update_rss(subscription, 3, now)
    actual_body = SubscriptionRss.find_by(subscription_id: subscription.id).body
    expected_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription · FeedRewind</title>
    <item>
      <title>Post 3</title>
      <link>https://blog/3</link>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 2</title>
      <link>https://blog/2</link>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 1</title>
      <link>https://blog/1</link>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Test Subscription added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal actual_body, expected_body
  end

  test "welcome + 1 to welcome + 2" do
    subscription = subscriptions(:test)
    blog = blogs(:test)
    before = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-05 00:00:00"))
    (1..5).each do |index|
      blog.blog_posts.create!(
        id: index,
        blog_id: blog.id,
        index: index,
        url: "https://blog/#{index}",
        title: "Post #{index}"
      )

      subscription.subscription_posts.create!(
        id: index,
        blog_post_id: index,
        subscription_id: subscription.id,
        published_at: index == 1 ? before.date : nil
      )
    end

    now = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-06 00:00:00"))
    UpdateRssService.update_rss(subscription, 1, now)
    actual_body = SubscriptionRss.find_by(subscription_id: subscription.id).body
    expected_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription · FeedRewind</title>
    <item>
      <title>Post 2</title>
      <link>https://blog/2</link>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 1</title>
      <link>https://blog/1</link>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Test Subscription added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal actual_body, expected_body
  end

  test "evict welcome" do
    subscription = subscriptions(:test)
    blog = blogs(:test)
    before = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-05 00:00:00"))
    (1..6).each do |index|
      blog.blog_posts.create!(
        id: index,
        blog_id: blog.id,
        index: index,
        url: "https://blog/#{index}",
        title: "Post #{index}"
      )

      subscription.subscription_posts.create!(
        id: index,
        blog_post_id: index,
        subscription_id: subscription.id,
        published_at: index <= 4 ? before.date : nil
      )
    end

    now = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-06 00:00:00"))
    silence_warnings do
      UpdateRssService::POSTS_IN_RSS = 5
    end
    UpdateRssService.update_rss(subscription, 1, now)
    actual_body = SubscriptionRss.find_by(subscription_id: subscription.id).body
    expected_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription · FeedRewind</title>
    <item>
      <title>Post 5</title>
      <link>https://blog/5</link>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 4</title>
      <link>https://blog/4</link>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 3</title>
      <link>https://blog/3</link>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 2</title>
      <link>https://blog/2</link>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 1</title>
      <link>https://blog/1</link>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal actual_body, expected_body
  end

  test "finish with welcome" do
    subscription = subscriptions(:test)
    blog = blogs(:test)
    before = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-05 00:00:00"))
    (1..3).each do |index|
      blog.blog_posts.create!(
        id: index,
        blog_id: blog.id,
        index: index,
        url: "https://blog/#{index}",
        title: "Post #{index}"
      )

      subscription.subscription_posts.create!(
        id: index,
        blog_post_id: index,
        subscription_id: subscription.id,
        published_at: index < 3 ? before.date : nil
      )
    end

    now = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-06 00:00:00"))
    silence_warnings do
      UpdateRssService::POSTS_IN_RSS = 5
    end
    UpdateRssService.update_rss(subscription, 1, now)
    actual_body = SubscriptionRss.find_by(subscription_id: subscription.id).body
    expected_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription · FeedRewind</title>
    <item>
      <title>You're all caught up with Test Subscription</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/add"&gt;Read something else?&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 3</title>
      <link>https://blog/3</link>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 2</title>
      <link>https://blog/2</link>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 1</title>
      <link>https://blog/1</link>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Test Subscription added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal actual_body, expected_body
  end

  test "finish without welcome" do
    subscription = subscriptions(:test)
    blog = blogs(:test)
    before = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-05 00:00:00"))
    (1..4).each do |index|
      blog.blog_posts.create!(
        id: index,
        blog_id: blog.id,
        index: index,
        url: "https://blog/#{index}",
        title: "Post #{index}"
      )

      subscription.subscription_posts.create!(
        id: index,
        blog_post_id: index,
        subscription_id: subscription.id,
        published_at: index < 4 ? before.date : nil
      )
    end

    now = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-06 00:00:00"))
    silence_warnings do
      UpdateRssService::POSTS_IN_RSS = 5
    end
    UpdateRssService.update_rss(subscription, 1, now)
    actual_body = SubscriptionRss.find_by(subscription_id: subscription.id).body
    expected_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription · FeedRewind</title>
    <item>
      <title>You're all caught up with Test Subscription</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/add"&gt;Read something else?&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 4</title>
      <link>https://blog/4</link>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 3</title>
      <link>https://blog/3</link>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 2</title>
      <link>https://blog/2</link>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 1</title>
      <link>https://blog/1</link>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal actual_body, expected_body
  end

  test "finish without welcome and first post" do
    subscription = subscriptions(:test)
    blog = blogs(:test)
    before = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-05 00:00:00"))
    (1..5).each do |index|
      blog.blog_posts.create!(
        id: index,
        blog_id: blog.id,
        index: index,
        url: "https://blog/#{index}",
        title: "Post #{index}"
      )

      subscription.subscription_posts.create!(
        id: index,
        blog_post_id: index,
        subscription_id: subscription.id,
        published_at: index < 5 ? before.date : nil
      )
    end

    now = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-06 00:00:00"))
    silence_warnings do
      UpdateRssService::POSTS_IN_RSS = 5
    end
    UpdateRssService.update_rss(subscription, 1, now)
    actual_body = SubscriptionRss.find_by(subscription_id: subscription.id).body
    expected_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription · FeedRewind</title>
    <item>
      <title>You're all caught up with Test Subscription</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/add"&gt;Read something else?&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 5</title>
      <link>https://blog/5</link>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 4</title>
      <link>https://blog/4</link>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 3</title>
      <link>https://blog/3</link>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 2</title>
      <link>https://blog/2</link>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal actual_body, expected_body
  end
end
