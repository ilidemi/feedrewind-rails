require "test_helper"

class UpdateRssServiceTest < ActiveSupport::TestCase
  test "init" do
    subscription = subscriptions(:test)
    UpdateRssService.init(subscription)
    actual_body = CurrentRss.find_by(subscription_id: subscription.id).body
    expected_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription · FeedRewind</title>
    <item>
      <title>Test Subscription added to FeedRewind</title>
      <link>https://rss-catchup.herokuapp.com/subscriptions/1</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
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
        is_published: false
      )
    end

    UpdateRssService.update_rss(subscription, 1)
    actual_body = CurrentRss.find_by(subscription_id: subscription.id).body
    expected_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription · FeedRewind</title>
    <item>
      <title>Post 1</title>
      <link>https://blog/1</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Test Subscription added to FeedRewind</title>
      <link>https://rss-catchup.herokuapp.com/subscriptions/1</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
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
        is_published: false
      )
    end

    UpdateRssService.update_rss(subscription, 3)
    actual_body = CurrentRss.find_by(subscription_id: subscription.id).body
    expected_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription · FeedRewind</title>
    <item>
      <title>Post 3</title>
      <link>https://blog/3</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 2</title>
      <link>https://blog/2</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 1</title>
      <link>https://blog/1</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Test Subscription added to FeedRewind</title>
      <link>https://rss-catchup.herokuapp.com/subscriptions/1</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
  </channel>
</rss>
    BODY
    assert_equal actual_body, expected_body
  end

  test "welcome + 1 to welcome + 2" do
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
        is_published: index == 1
      )
    end

    UpdateRssService.update_rss(subscription, 1)
    actual_body = CurrentRss.find_by(subscription_id: subscription.id).body
    expected_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription · FeedRewind</title>
    <item>
      <title>Post 2</title>
      <link>https://blog/2</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 1</title>
      <link>https://blog/1</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Test Subscription added to FeedRewind</title>
      <link>https://rss-catchup.herokuapp.com/subscriptions/1</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
  </channel>
</rss>
    BODY
    assert_equal actual_body, expected_body
  end

  test "evict welcome" do
    subscription = subscriptions(:test)
    blog = blogs(:test)
    (1..17).each do |index|
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
        is_published: index <= 15
      )
    end

    UpdateRssService.update_rss(subscription, 1)
    actual_body = CurrentRss.find_by(subscription_id: subscription.id).body
    expected_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription · FeedRewind</title>
    <item>
      <title>Post 16</title>
      <link>https://blog/16</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 15</title>
      <link>https://blog/15</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 14</title>
      <link>https://blog/14</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 13</title>
      <link>https://blog/13</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 12</title>
      <link>https://blog/12</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 11</title>
      <link>https://blog/11</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 10</title>
      <link>https://blog/10</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 9</title>
      <link>https://blog/9</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 8</title>
      <link>https://blog/8</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 7</title>
      <link>https://blog/7</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 6</title>
      <link>https://blog/6</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 5</title>
      <link>https://blog/5</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 4</title>
      <link>https://blog/4</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 3</title>
      <link>https://blog/3</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 2</title>
      <link>https://blog/2</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
  </channel>
</rss>
    BODY
    assert_equal actual_body, expected_body
  end

  test "finish with welcome" do
    subscription = subscriptions(:test)
    blog = blogs(:test)
    (1..14).each do |index|
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
        is_published: index < 14
      )
    end

    UpdateRssService.update_rss(subscription, 1)
    actual_body = CurrentRss.find_by(subscription_id: subscription.id).body
    expected_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription · FeedRewind</title>
    <item>
      <title>You're all caught up with Test Subscription</title>
      <link>https://rss-catchup.herokuapp.com/subscriptions/1</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/add"&gt;Read something else?&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 14</title>
      <link>https://blog/14</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 13</title>
      <link>https://blog/13</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 12</title>
      <link>https://blog/12</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 11</title>
      <link>https://blog/11</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 10</title>
      <link>https://blog/10</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 9</title>
      <link>https://blog/9</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 8</title>
      <link>https://blog/8</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 7</title>
      <link>https://blog/7</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 6</title>
      <link>https://blog/6</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 5</title>
      <link>https://blog/5</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 4</title>
      <link>https://blog/4</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 3</title>
      <link>https://blog/3</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 2</title>
      <link>https://blog/2</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 1</title>
      <link>https://blog/1</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Test Subscription added to FeedRewind</title>
      <link>https://rss-catchup.herokuapp.com/subscriptions/1</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
  </channel>
</rss>
    BODY
    assert_equal actual_body, expected_body
  end

  test "finish without welcome" do
    subscription = subscriptions(:test)
    blog = blogs(:test)
    (1..15).each do |index|
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
        is_published: index < 15
      )
    end

    UpdateRssService.update_rss(subscription, 1)
    actual_body = CurrentRss.find_by(subscription_id: subscription.id).body
    expected_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription · FeedRewind</title>
    <item>
      <title>You're all caught up with Test Subscription</title>
      <link>https://rss-catchup.herokuapp.com/subscriptions/1</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/add"&gt;Read something else?&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 15</title>
      <link>https://blog/15</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 14</title>
      <link>https://blog/14</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 13</title>
      <link>https://blog/13</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 12</title>
      <link>https://blog/12</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 11</title>
      <link>https://blog/11</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 10</title>
      <link>https://blog/10</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 9</title>
      <link>https://blog/9</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 8</title>
      <link>https://blog/8</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 7</title>
      <link>https://blog/7</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 6</title>
      <link>https://blog/6</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 5</title>
      <link>https://blog/5</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 4</title>
      <link>https://blog/4</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 3</title>
      <link>https://blog/3</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 2</title>
      <link>https://blog/2</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 1</title>
      <link>https://blog/1</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
  </channel>
</rss>
    BODY
    assert_equal actual_body, expected_body
  end

  test "finish without welcome and first post" do
    subscription = subscriptions(:test)
    blog = blogs(:test)
    (1..16).each do |index|
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
        is_published: index < 16
      )
    end

    UpdateRssService.update_rss(subscription, 1)
    actual_body = CurrentRss.find_by(subscription_id: subscription.id).body
    expected_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription · FeedRewind</title>
    <item>
      <title>You're all caught up with Test Subscription</title>
      <link>https://rss-catchup.herokuapp.com/subscriptions/1</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/add"&gt;Read something else?&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 16</title>
      <link>https://blog/16</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 15</title>
      <link>https://blog/15</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 14</title>
      <link>https://blog/14</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 13</title>
      <link>https://blog/13</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 12</title>
      <link>https://blog/12</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 11</title>
      <link>https://blog/11</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 10</title>
      <link>https://blog/10</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 9</title>
      <link>https://blog/9</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 8</title>
      <link>https://blog/8</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 7</title>
      <link>https://blog/7</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 6</title>
      <link>https://blog/6</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 5</title>
      <link>https://blog/5</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 4</title>
      <link>https://blog/4</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 3</title>
      <link>https://blog/3</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
    <item>
      <title>Post 2</title>
      <link>https://blog/2</link>
      <description>&lt;a href="https://rss-catchup.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
    </item>
  </channel>
</rss>
    BODY
    assert_equal actual_body, expected_body
  end
end
