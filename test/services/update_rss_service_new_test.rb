require "test_helper"

#noinspection HttpUrlsUsage
class UpdateRssServiceNewTest < ActiveSupport::TestCase
  test "init with 0 posts" do
    now = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-05 00:00:00"))
    subscription = create_subscription(1, now.date, 5, 0, fri_count: 1)

    UpdateRssServiceNew.init_subscription(subscription, false, now)

    actual_sub_body = SubscriptionRss.find_by(subscription_id: subscription.id).body
    expected_sub_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription 1 · FeedRewind</title>
    <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
    <item>
      <title>Test Subscription 1 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <guid isPermaLink=\"false\">02d00b67b9732798e803e344a5e57d80e3f7a620991f9cd5f2256ff8644de37a</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal expected_sub_body, actual_sub_body

    actual_user_body = UserRss.find_by(user_id: subscription.user.id).body
    expected_user_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>FeedRewind</title>
    <link>https://feedrewind.herokuapp.com</link>
    <item>
      <title>Test Subscription 1 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <guid isPermaLink=\"false\">02d00b67b9732798e803e344a5e57d80e3f7a620991f9cd5f2256ff8644de37a</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal expected_user_body, actual_user_body
  end

  test "init with schedule but 0 posts" do
    now = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-05 00:00:00"))
    subscription = create_subscription(1, now.date, 5, 0, thu_count: 1)

    UpdateRssServiceNew.init_subscription(subscription, false, now)

    actual_sub_body = SubscriptionRss.find_by(subscription_id: subscription.id).body
    expected_sub_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription 1 · FeedRewind</title>
    <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
    <item>
      <title>Test Subscription 1 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <guid isPermaLink=\"false\">02d00b67b9732798e803e344a5e57d80e3f7a620991f9cd5f2256ff8644de37a</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal expected_sub_body, actual_sub_body

    actual_user_body = UserRss.find_by(user_id: subscription.user.id).body
    expected_user_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>FeedRewind</title>
    <link>https://feedrewind.herokuapp.com</link>
    <item>
      <title>Test Subscription 1 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <guid isPermaLink=\"false\">02d00b67b9732798e803e344a5e57d80e3f7a620991f9cd5f2256ff8644de37a</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal expected_user_body, actual_user_body
  end

  test "init with some posts" do
    now = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-05 00:00:00"))
    subscription = create_subscription(1, now.date, 5, 0, thu_count: 2, fri_count: 2)

    UpdateRssServiceNew.init_subscription(subscription, true, now)

    actual_sub_body = SubscriptionRss.find_by(subscription_id: subscription.id).body
    expected_sub_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription 1 · FeedRewind</title>
    <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
    <item>
      <title>Post 2</title>
      <link>https://blog1/2</link>
      <guid isPermaLink=\"false\">37834f2f25762f23e1f74a531cbe445db73d6765ebe60878a7dfbecd7d4af6e1</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 1</title>
      <link>https://blog1/1</link>
      <guid isPermaLink=\"false\">16dc368a89b428b2485484313ba67a3912ca03f2b2b42429174a4f8b3dc84e44</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Test Subscription 1 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <guid isPermaLink=\"false\">02d00b67b9732798e803e344a5e57d80e3f7a620991f9cd5f2256ff8644de37a</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal expected_sub_body, actual_sub_body

    actual_user_body = UserRss.find_by(user_id: subscription.user.id).body
    expected_user_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>FeedRewind</title>
    <link>https://feedrewind.herokuapp.com</link>
    <item>
      <title>Post 2</title>
      <link>https://blog1/2</link>
      <guid isPermaLink=\"false\">37834f2f25762f23e1f74a531cbe445db73d6765ebe60878a7dfbecd7d4af6e1</guid>
      <description>from Test Subscription 1&lt;br&gt;&lt;br&gt;&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 1</title>
      <link>https://blog1/1</link>
      <guid isPermaLink=\"false\">16dc368a89b428b2485484313ba67a3912ca03f2b2b42429174a4f8b3dc84e44</guid>
      <description>from Test Subscription 1&lt;br&gt;&lt;br&gt;&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Test Subscription 1 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <guid isPermaLink=\"false\">02d00b67b9732798e803e344a5e57d80e3f7a620991f9cd5f2256ff8644de37a</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal expected_user_body, actual_user_body
  end

  test "init another with 0 posts" do
    now = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-05 00:00:00"))
    subscription1 = create_subscription(1, now.date, 5, 0, fri_count: 1)
    before = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-04 00:00:00"))
    create_subscription(2, before.date, 5, 1, wed_count: 1)

    UpdateRssServiceNew.init_subscription(subscription1, false, now)

    actual_sub_body = SubscriptionRss.find_by(subscription_id: subscription1.id).body
    expected_sub_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription 1 · FeedRewind</title>
    <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
    <item>
      <title>Test Subscription 1 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <guid isPermaLink=\"false\">02d00b67b9732798e803e344a5e57d80e3f7a620991f9cd5f2256ff8644de37a</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal expected_sub_body, actual_sub_body

    actual_user_body = UserRss.find_by(user_id: subscription1.user.id).body
    expected_user_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>FeedRewind</title>
    <link>https://feedrewind.herokuapp.com</link>
    <item>
      <title>Test Subscription 1 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <guid isPermaLink=\"false\">02d00b67b9732798e803e344a5e57d80e3f7a620991f9cd5f2256ff8644de37a</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 1</title>
      <link>https://blog2/1</link>
      <guid isPermaLink=\"false\">43974ed74066b207c30ffd0fed5146762e6c60745ac977004bc14507c7c42b50</guid>
      <description>from Test Subscription 2&lt;br&gt;&lt;br&gt;&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/2\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Wed, 04 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Test Subscription 2 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/2</link>
      <guid isPermaLink=\"false\">ebd09a71ff012c43b03f497b6551b9b41fe889ecc73aeceb2ab6c002bfbb6a91</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/2\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Wed, 04 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal expected_user_body, actual_user_body
  end

  test "init another with schedule but 0 posts" do
    now = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-05 00:00:00"))
    subscription1 = create_subscription(1, now.date, 5, 0, thu_count: 1)
    before = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-04 00:00:00"))
    create_subscription(2, before.date, 5, 1, wed_count: 1)

    UpdateRssServiceNew.init_subscription(subscription1, false, now)

    actual_sub_body = SubscriptionRss.find_by(subscription_id: subscription1.id).body
    expected_sub_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription 1 · FeedRewind</title>
    <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
    <item>
      <title>Test Subscription 1 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <guid isPermaLink=\"false\">02d00b67b9732798e803e344a5e57d80e3f7a620991f9cd5f2256ff8644de37a</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal expected_sub_body, actual_sub_body

    actual_user_body = UserRss.find_by(user_id: subscription1.user.id).body
    expected_user_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>FeedRewind</title>
    <link>https://feedrewind.herokuapp.com</link>
    <item>
      <title>Test Subscription 1 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <guid isPermaLink=\"false\">02d00b67b9732798e803e344a5e57d80e3f7a620991f9cd5f2256ff8644de37a</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 1</title>
      <link>https://blog2/1</link>
      <guid isPermaLink=\"false\">43974ed74066b207c30ffd0fed5146762e6c60745ac977004bc14507c7c42b50</guid>
      <description>from Test Subscription 2&lt;br&gt;&lt;br&gt;&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/2\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Wed, 04 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Test Subscription 2 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/2</link>
      <guid isPermaLink=\"false\">ebd09a71ff012c43b03f497b6551b9b41fe889ecc73aeceb2ab6c002bfbb6a91</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/2\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Wed, 04 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal expected_user_body, actual_user_body
  end

  test "init another with some posts" do
    now = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-05 00:00:00"))
    subscription1 = create_subscription(1, now.date, 5, 0, thu_count: 2, fri_count: 2)
    before = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-04 00:00:00"))
    create_subscription(2, before.date, 5, 1, wed_count: 1)

    UpdateRssServiceNew.init_subscription(subscription1, true, now)

    actual_sub_body = SubscriptionRss.find_by(subscription_id: subscription1.id).body
    expected_sub_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription 1 · FeedRewind</title>
    <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
    <item>
      <title>Post 2</title>
      <link>https://blog1/2</link>
      <guid isPermaLink=\"false\">37834f2f25762f23e1f74a531cbe445db73d6765ebe60878a7dfbecd7d4af6e1</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 1</title>
      <link>https://blog1/1</link>
      <guid isPermaLink=\"false\">16dc368a89b428b2485484313ba67a3912ca03f2b2b42429174a4f8b3dc84e44</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Test Subscription 1 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <guid isPermaLink=\"false\">02d00b67b9732798e803e344a5e57d80e3f7a620991f9cd5f2256ff8644de37a</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal expected_sub_body, actual_sub_body

    actual_user_body = UserRss.find_by(user_id: subscription1.user.id).body
    expected_user_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>FeedRewind</title>
    <link>https://feedrewind.herokuapp.com</link>
    <item>
      <title>Post 2</title>
      <link>https://blog1/2</link>
      <guid isPermaLink=\"false\">37834f2f25762f23e1f74a531cbe445db73d6765ebe60878a7dfbecd7d4af6e1</guid>
      <description>from Test Subscription 1&lt;br&gt;&lt;br&gt;&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 1</title>
      <link>https://blog1/1</link>
      <guid isPermaLink=\"false\">16dc368a89b428b2485484313ba67a3912ca03f2b2b42429174a4f8b3dc84e44</guid>
      <description>from Test Subscription 1&lt;br&gt;&lt;br&gt;&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Test Subscription 1 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <guid isPermaLink=\"false\">02d00b67b9732798e803e344a5e57d80e3f7a620991f9cd5f2256ff8644de37a</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 1</title>
      <link>https://blog2/1</link>
      <guid isPermaLink=\"false\">43974ed74066b207c30ffd0fed5146762e6c60745ac977004bc14507c7c42b50</guid>
      <description>from Test Subscription 2&lt;br&gt;&lt;br&gt;&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/2\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Wed, 04 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Test Subscription 2 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/2</link>
      <guid isPermaLink=\"false\">ebd09a71ff012c43b03f497b6551b9b41fe889ecc73aeceb2ab6c002bfbb6a91</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/2\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Wed, 04 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal expected_user_body, actual_user_body
  end

  test "update one" do
    before = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-05 00:00:00"))
    subscription = create_subscription(1, before.date, 5, 0, thu_count: 2, fri_count: 2)
    UpdateRssServiceNew.init_subscription(subscription, true, before)

    now = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-06 00:00:00"))
    UpdateRssServiceNew.update_for_user(subscription.user_id, now)

    actual_sub_body = SubscriptionRss.find_by(subscription_id: subscription.id).body
    expected_sub_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription 1 · FeedRewind</title>
    <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
    <item>
      <title>Post 4</title>
      <link>https://blog1/4</link>
      <guid isPermaLink=\"false\">5ef6fdf32513aa7cd11f72beccf132b9224d33f271471fff402742887a171edf</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 3</title>
      <link>https://blog1/3</link>
      <guid isPermaLink=\"false\">454f63ac30c8322997ef025edff6abd23e0dbe7b8a3d5126a894e4a168c1b59b</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 2</title>
      <link>https://blog1/2</link>
      <guid isPermaLink=\"false\">37834f2f25762f23e1f74a531cbe445db73d6765ebe60878a7dfbecd7d4af6e1</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 1</title>
      <link>https://blog1/1</link>
      <guid isPermaLink=\"false\">16dc368a89b428b2485484313ba67a3912ca03f2b2b42429174a4f8b3dc84e44</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Test Subscription 1 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <guid isPermaLink=\"false\">02d00b67b9732798e803e344a5e57d80e3f7a620991f9cd5f2256ff8644de37a</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal expected_sub_body, actual_sub_body

    actual_user_body = UserRss.find_by(user_id: subscription.user.id).body
    expected_user_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>FeedRewind</title>
    <link>https://feedrewind.herokuapp.com</link>
    <item>
      <title>Post 4</title>
      <link>https://blog1/4</link>
      <guid isPermaLink=\"false\">5ef6fdf32513aa7cd11f72beccf132b9224d33f271471fff402742887a171edf</guid>
      <description>from Test Subscription 1&lt;br&gt;&lt;br&gt;&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 3</title>
      <link>https://blog1/3</link>
      <guid isPermaLink=\"false\">454f63ac30c8322997ef025edff6abd23e0dbe7b8a3d5126a894e4a168c1b59b</guid>
      <description>from Test Subscription 1&lt;br&gt;&lt;br&gt;&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 2</title>
      <link>https://blog1/2</link>
      <guid isPermaLink=\"false\">37834f2f25762f23e1f74a531cbe445db73d6765ebe60878a7dfbecd7d4af6e1</guid>
      <description>from Test Subscription 1&lt;br&gt;&lt;br&gt;&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 1</title>
      <link>https://blog1/1</link>
      <guid isPermaLink=\"false\">16dc368a89b428b2485484313ba67a3912ca03f2b2b42429174a4f8b3dc84e44</guid>
      <description>from Test Subscription 1&lt;br&gt;&lt;br&gt;&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Test Subscription 1 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <guid isPermaLink=\"false\">02d00b67b9732798e803e344a5e57d80e3f7a620991f9cd5f2256ff8644de37a</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal expected_user_body, actual_user_body
  end

  test "update multiple at once" do
    before_before = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-04 00:00:00"))
    subscription1 = create_subscription(1, before_before.date, 5, 0, wed_count: 2, fri_count: 2)
    UpdateRssServiceNew.init_subscription(subscription1, true, before_before)
    before = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-05 00:00:00"))
    subscription2 = create_subscription(2, before.date, 5, 0, thu_count: 1, fri_count: 1)
    UpdateRssServiceNew.init_subscription(subscription2, true, before)

    now = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-06 00:00:00"))
    UpdateRssServiceNew.update_for_user(subscription1.user_id, now)

    actual_sub1_body = SubscriptionRss.find_by(subscription_id: subscription1.id).body
    expected_sub1_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription 1 · FeedRewind</title>
    <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
    <item>
      <title>Post 4</title>
      <link>https://blog1/4</link>
      <guid isPermaLink=\"false\">5ef6fdf32513aa7cd11f72beccf132b9224d33f271471fff402742887a171edf</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 3</title>
      <link>https://blog1/3</link>
      <guid isPermaLink=\"false\">454f63ac30c8322997ef025edff6abd23e0dbe7b8a3d5126a894e4a168c1b59b</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 2</title>
      <link>https://blog1/2</link>
      <guid isPermaLink=\"false\">37834f2f25762f23e1f74a531cbe445db73d6765ebe60878a7dfbecd7d4af6e1</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Wed, 04 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 1</title>
      <link>https://blog1/1</link>
      <guid isPermaLink=\"false\">16dc368a89b428b2485484313ba67a3912ca03f2b2b42429174a4f8b3dc84e44</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Wed, 04 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Test Subscription 1 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <guid isPermaLink=\"false\">02d00b67b9732798e803e344a5e57d80e3f7a620991f9cd5f2256ff8644de37a</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Wed, 04 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal expected_sub1_body, actual_sub1_body

    actual_sub2_body = SubscriptionRss.find_by(subscription_id: subscription2.id).body
    expected_sub2_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription 2 · FeedRewind</title>
    <link>https://feedrewind.herokuapp.com/subscriptions/2</link>
    <item>
      <title>Post 2</title>
      <link>https://blog2/2</link>
      <guid isPermaLink=\"false\">c17edaae86e4016a583e098582f6dbf3eccade8ef83747df9ba617ded9d31309</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/2\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 1</title>
      <link>https://blog2/1</link>
      <guid isPermaLink=\"false\">43974ed74066b207c30ffd0fed5146762e6c60745ac977004bc14507c7c42b50</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/2\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Test Subscription 2 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/2</link>
      <guid isPermaLink=\"false\">ebd09a71ff012c43b03f497b6551b9b41fe889ecc73aeceb2ab6c002bfbb6a91</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/2\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal expected_sub2_body, actual_sub2_body

    actual_user_body = UserRss.find_by(user_id: subscription1.user.id).body
    expected_user_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>FeedRewind</title>
    <link>https://feedrewind.herokuapp.com</link>
    <item>
      <title>Post 2</title>
      <link>https://blog2/2</link>
      <guid isPermaLink=\"false\">c17edaae86e4016a583e098582f6dbf3eccade8ef83747df9ba617ded9d31309</guid>
      <description>from Test Subscription 2&lt;br&gt;&lt;br&gt;&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/2\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 4</title>
      <link>https://blog1/4</link>
      <guid isPermaLink=\"false\">5ef6fdf32513aa7cd11f72beccf132b9224d33f271471fff402742887a171edf</guid>
      <description>from Test Subscription 1&lt;br&gt;&lt;br&gt;&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 3</title>
      <link>https://blog1/3</link>
      <guid isPermaLink=\"false\">454f63ac30c8322997ef025edff6abd23e0dbe7b8a3d5126a894e4a168c1b59b</guid>
      <description>from Test Subscription 1&lt;br&gt;&lt;br&gt;&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 1</title>
      <link>https://blog2/1</link>
      <guid isPermaLink=\"false\">43974ed74066b207c30ffd0fed5146762e6c60745ac977004bc14507c7c42b50</guid>
      <description>from Test Subscription 2&lt;br&gt;&lt;br&gt;&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/2\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Test Subscription 2 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/2</link>
      <guid isPermaLink=\"false\">ebd09a71ff012c43b03f497b6551b9b41fe889ecc73aeceb2ab6c002bfbb6a91</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/2\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 2</title>
      <link>https://blog1/2</link>
      <guid isPermaLink=\"false\">37834f2f25762f23e1f74a531cbe445db73d6765ebe60878a7dfbecd7d4af6e1</guid>
      <description>from Test Subscription 1&lt;br&gt;&lt;br&gt;&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Wed, 04 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 1</title>
      <link>https://blog1/1</link>
      <guid isPermaLink=\"false\">16dc368a89b428b2485484313ba67a3912ca03f2b2b42429174a4f8b3dc84e44</guid>
      <description>from Test Subscription 1&lt;br&gt;&lt;br&gt;&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Wed, 04 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Test Subscription 1 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <guid isPermaLink=\"false\">02d00b67b9732798e803e344a5e57d80e3f7a620991f9cd5f2256ff8644de37a</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Wed, 04 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal expected_user_body, actual_user_body
  end

  test "update some but not all" do
    before_before = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-04 00:00:00"))
    subscription1 = create_subscription(1, before_before.date, 5, 0, wed_count: 1, fri_count: 1)
    UpdateRssServiceNew.init_subscription(subscription1, true, before_before)
    before = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-05 00:00:00"))
    subscription2 = create_subscription(2, before.date, 5, 0, thu_count: 1)
    UpdateRssServiceNew.init_subscription(subscription2, true, before)

    now = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-06 00:00:00"))
    UpdateRssServiceNew.update_for_user(subscription1.user_id, now)

    actual_sub1_body = SubscriptionRss.find_by(subscription_id: subscription1.id).body
    expected_sub1_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription 1 · FeedRewind</title>
    <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
    <item>
      <title>Post 2</title>
      <link>https://blog1/2</link>
      <guid isPermaLink=\"false\">37834f2f25762f23e1f74a531cbe445db73d6765ebe60878a7dfbecd7d4af6e1</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 1</title>
      <link>https://blog1/1</link>
      <guid isPermaLink=\"false\">16dc368a89b428b2485484313ba67a3912ca03f2b2b42429174a4f8b3dc84e44</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Wed, 04 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Test Subscription 1 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <guid isPermaLink=\"false\">02d00b67b9732798e803e344a5e57d80e3f7a620991f9cd5f2256ff8644de37a</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Wed, 04 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal expected_sub1_body, actual_sub1_body

    actual_sub2_body = SubscriptionRss.find_by(subscription_id: subscription2.id).body
    expected_sub2_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription 2 · FeedRewind</title>
    <link>https://feedrewind.herokuapp.com/subscriptions/2</link>
    <item>
      <title>Post 1</title>
      <link>https://blog2/1</link>
      <guid isPermaLink=\"false\">43974ed74066b207c30ffd0fed5146762e6c60745ac977004bc14507c7c42b50</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/2\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Test Subscription 2 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/2</link>
      <guid isPermaLink=\"false\">ebd09a71ff012c43b03f497b6551b9b41fe889ecc73aeceb2ab6c002bfbb6a91</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/2\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal expected_sub2_body, actual_sub2_body

    actual_user_body = UserRss.find_by(user_id: subscription1.user.id).body
    expected_user_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>FeedRewind</title>
    <link>https://feedrewind.herokuapp.com</link>
    <item>
      <title>Post 2</title>
      <link>https://blog1/2</link>
      <guid isPermaLink=\"false\">37834f2f25762f23e1f74a531cbe445db73d6765ebe60878a7dfbecd7d4af6e1</guid>
      <description>from Test Subscription 1&lt;br&gt;&lt;br&gt;&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 1</title>
      <link>https://blog2/1</link>
      <guid isPermaLink=\"false\">43974ed74066b207c30ffd0fed5146762e6c60745ac977004bc14507c7c42b50</guid>
      <description>from Test Subscription 2&lt;br&gt;&lt;br&gt;&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/2\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Test Subscription 2 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/2</link>
      <guid isPermaLink=\"false\">ebd09a71ff012c43b03f497b6551b9b41fe889ecc73aeceb2ab6c002bfbb6a91</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/2\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 1</title>
      <link>https://blog1/1</link>
      <guid isPermaLink=\"false\">16dc368a89b428b2485484313ba67a3912ca03f2b2b42429174a4f8b3dc84e44</guid>
      <description>from Test Subscription 1&lt;br&gt;&lt;br&gt;&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Wed, 04 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Test Subscription 1 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <guid isPermaLink=\"false\">02d00b67b9732798e803e344a5e57d80e3f7a620991f9cd5f2256ff8644de37a</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Wed, 04 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal expected_user_body, actual_user_body
  end

  test "update none" do
    before_before = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-04 00:00:00"))
    subscription1 = create_subscription(1, before_before.date, 5, 0, wed_count: 1)
    UpdateRssServiceNew.init_subscription(subscription1, true, before_before)
    before = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-05 00:00:00"))
    subscription2 = create_subscription(2, before.date, 5, 0, thu_count: 1)
    UpdateRssServiceNew.init_subscription(subscription2, true, before)

    now = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-06 00:00:00"))
    UpdateRssServiceNew.update_for_user(subscription1.user_id, now)

    actual_sub1_body = SubscriptionRss.find_by(subscription_id: subscription1.id).body
    expected_sub1_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription 1 · FeedRewind</title>
    <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
    <item>
      <title>Post 1</title>
      <link>https://blog1/1</link>
      <guid isPermaLink=\"false\">16dc368a89b428b2485484313ba67a3912ca03f2b2b42429174a4f8b3dc84e44</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Wed, 04 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Test Subscription 1 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <guid isPermaLink=\"false\">02d00b67b9732798e803e344a5e57d80e3f7a620991f9cd5f2256ff8644de37a</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Wed, 04 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal expected_sub1_body, actual_sub1_body

    actual_sub2_body = SubscriptionRss.find_by(subscription_id: subscription2.id).body
    expected_sub2_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription 2 · FeedRewind</title>
    <link>https://feedrewind.herokuapp.com/subscriptions/2</link>
    <item>
      <title>Post 1</title>
      <link>https://blog2/1</link>
      <guid isPermaLink=\"false\">43974ed74066b207c30ffd0fed5146762e6c60745ac977004bc14507c7c42b50</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/2\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Test Subscription 2 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/2</link>
      <guid isPermaLink=\"false\">ebd09a71ff012c43b03f497b6551b9b41fe889ecc73aeceb2ab6c002bfbb6a91</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/2\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal expected_sub2_body, actual_sub2_body

    actual_user_body = UserRss.find_by(user_id: subscription1.user.id).body
    expected_user_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>FeedRewind</title>
    <link>https://feedrewind.herokuapp.com</link>
    <item>
      <title>Post 1</title>
      <link>https://blog2/1</link>
      <guid isPermaLink=\"false\">43974ed74066b207c30ffd0fed5146762e6c60745ac977004bc14507c7c42b50</guid>
      <description>from Test Subscription 2&lt;br&gt;&lt;br&gt;&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/2\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Test Subscription 2 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/2</link>
      <guid isPermaLink=\"false\">ebd09a71ff012c43b03f497b6551b9b41fe889ecc73aeceb2ab6c002bfbb6a91</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/2\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 1</title>
      <link>https://blog1/1</link>
      <guid isPermaLink=\"false\">16dc368a89b428b2485484313ba67a3912ca03f2b2b42429174a4f8b3dc84e44</guid>
      <description>from Test Subscription 1&lt;br&gt;&lt;br&gt;&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Wed, 04 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Test Subscription 1 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <guid isPermaLink=\"false\">02d00b67b9732798e803e344a5e57d80e3f7a620991f9cd5f2256ff8644de37a</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Wed, 04 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal expected_user_body, actual_user_body
  end

  test "evict welcome" do
    before = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-05 00:00:00"))
    subscription = create_subscription(1, before.date, 6, 4, fri_count: 1)
    UpdateRssServiceNew.init_subscription(subscription, true, before)

    now = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-06 00:00:00"))
    silence_warnings { UpdateRssServiceNew::POSTS_IN_RSS = 5 }
    UpdateRssServiceNew.update_for_user(subscription.user_id, now)

    actual_sub_body = SubscriptionRss.find_by(subscription_id: subscription.id).body
    expected_sub_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription 1 · FeedRewind</title>
    <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
    <item>
      <title>Post 5</title>
      <link>https://blog1/5</link>
      <guid isPermaLink=\"false\">1253e9373e781b7500266caa55150e08e210bc8cd8cc70d89985e3600155e860</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 4</title>
      <link>https://blog1/4</link>
      <guid isPermaLink=\"false\">5ef6fdf32513aa7cd11f72beccf132b9224d33f271471fff402742887a171edf</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 3</title>
      <link>https://blog1/3</link>
      <guid isPermaLink=\"false\">454f63ac30c8322997ef025edff6abd23e0dbe7b8a3d5126a894e4a168c1b59b</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 2</title>
      <link>https://blog1/2</link>
      <guid isPermaLink=\"false\">37834f2f25762f23e1f74a531cbe445db73d6765ebe60878a7dfbecd7d4af6e1</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 1</title>
      <link>https://blog1/1</link>
      <guid isPermaLink=\"false\">16dc368a89b428b2485484313ba67a3912ca03f2b2b42429174a4f8b3dc84e44</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal expected_sub_body, actual_sub_body
  end

  test "finish with welcome" do
    before = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-05 00:00:00"))
    subscription = create_subscription(1, before.date, 3, 2, fri_count: 1)
    UpdateRssServiceNew.init_subscription(subscription, true, before)

    now = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-06 00:00:00"))
    silence_warnings { UpdateRssServiceNew::POSTS_IN_RSS = 5 }
    UpdateRssServiceNew.update_for_user(subscription.user_id, now)

    actual_sub_body = SubscriptionRss.find_by(subscription_id: subscription.id).body
    expected_sub_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription 1 · FeedRewind</title>
    <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
    <item>
      <title>You're all caught up with Test Subscription 1</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <guid isPermaLink=\"false\">3fe72a84a4c123fd67940ca3f338f28aa8de4991a1e444991f42aa7a1549e174</guid>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/add"&gt;Read something else?&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 3</title>
      <link>https://blog1/3</link>
      <guid isPermaLink=\"false\">454f63ac30c8322997ef025edff6abd23e0dbe7b8a3d5126a894e4a168c1b59b</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 2</title>
      <link>https://blog1/2</link>
      <guid isPermaLink=\"false\">37834f2f25762f23e1f74a531cbe445db73d6765ebe60878a7dfbecd7d4af6e1</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 1</title>
      <link>https://blog1/1</link>
      <guid isPermaLink=\"false\">16dc368a89b428b2485484313ba67a3912ca03f2b2b42429174a4f8b3dc84e44</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Test Subscription 1 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <guid isPermaLink=\"false\">02d00b67b9732798e803e344a5e57d80e3f7a620991f9cd5f2256ff8644de37a</guid>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/1"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal expected_sub_body, actual_sub_body
  end

  test "finish without welcome" do
    before = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-05 00:00:00"))
    subscription = create_subscription(1, before.date, 4, 3, fri_count: 1)
    UpdateRssServiceNew.init_subscription(subscription, true, before)

    now = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-06 00:00:00"))
    silence_warnings { UpdateRssServiceNew::POSTS_IN_RSS = 5 }
    UpdateRssServiceNew.update_for_user(subscription.user_id, now)

    actual_sub_body = SubscriptionRss.find_by(subscription_id: subscription.id).body
    expected_sub_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription 1 · FeedRewind</title>
    <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
    <item>
      <title>You're all caught up with Test Subscription 1</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <guid isPermaLink=\"false\">3fe72a84a4c123fd67940ca3f338f28aa8de4991a1e444991f42aa7a1549e174</guid>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/add"&gt;Read something else?&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 4</title>
      <link>https://blog1/4</link>
      <guid isPermaLink=\"false\">5ef6fdf32513aa7cd11f72beccf132b9224d33f271471fff402742887a171edf</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 3</title>
      <link>https://blog1/3</link>
      <guid isPermaLink=\"false\">454f63ac30c8322997ef025edff6abd23e0dbe7b8a3d5126a894e4a168c1b59b</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 2</title>
      <link>https://blog1/2</link>
      <guid isPermaLink=\"false\">37834f2f25762f23e1f74a531cbe445db73d6765ebe60878a7dfbecd7d4af6e1</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 1</title>
      <link>https://blog1/1</link>
      <guid isPermaLink=\"false\">16dc368a89b428b2485484313ba67a3912ca03f2b2b42429174a4f8b3dc84e44</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal expected_sub_body, actual_sub_body
  end

  test "finish without welcome and first post" do
    before = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-05 00:00:00"))
    subscription = create_subscription(1, before.date, 5, 4, fri_count: 1)
    UpdateRssServiceNew.init_subscription(subscription, true, before)

    now = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-06 00:00:00"))
    silence_warnings { UpdateRssServiceNew::POSTS_IN_RSS = 5 }
    UpdateRssServiceNew.update_for_user(subscription.user_id, now)

    actual_sub_body = SubscriptionRss.find_by(subscription_id: subscription.id).body
    expected_sub_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription 1 · FeedRewind</title>
    <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
    <item>
      <title>You're all caught up with Test Subscription 1</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <guid isPermaLink=\"false\">3fe72a84a4c123fd67940ca3f338f28aa8de4991a1e444991f42aa7a1549e174</guid>
      <description>&lt;a href="https://feedrewind.herokuapp.com/subscriptions/add"&gt;Read something else?&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 5</title>
      <link>https://blog1/5</link>
      <guid isPermaLink=\"false\">1253e9373e781b7500266caa55150e08e210bc8cd8cc70d89985e3600155e860</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 4</title>
      <link>https://blog1/4</link>
      <guid isPermaLink=\"false\">5ef6fdf32513aa7cd11f72beccf132b9224d33f271471fff402742887a171edf</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 3</title>
      <link>https://blog1/3</link>
      <guid isPermaLink=\"false\">454f63ac30c8322997ef025edff6abd23e0dbe7b8a3d5126a894e4a168c1b59b</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 2</title>
      <link>https://blog1/2</link>
      <guid isPermaLink=\"false\">37834f2f25762f23e1f74a531cbe445db73d6765ebe60878a7dfbecd7d4af6e1</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal expected_sub_body, actual_sub_body
  end

  test "is_paused handling" do
    before = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-05 00:00:00"))
    subscription = create_subscription(1, before.date, 5, 0, fri_count: 1)
    UpdateRssServiceNew.init_subscription(subscription, true, before)
    subscription.update_attribute(:is_paused, true)

    now = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-06 00:00:00"))
    UpdateRssServiceNew.update_for_user(subscription.user_id, now)

    actual_sub_body = SubscriptionRss.find_by(subscription_id: subscription.id).body
    expected_sub_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test Subscription 1 · FeedRewind</title>
    <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
    <item>
      <title>Test Subscription 1 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <guid isPermaLink=\"false\">02d00b67b9732798e803e344a5e57d80e3f7a620991f9cd5f2256ff8644de37a</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal expected_sub_body, actual_sub_body
  end

  test "user feed stable sort" do
    date1 = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-03 00:00:00"))
    subscription1 = create_subscription(1, date1.date, 5, 0, fri_count: 2)

    date2 = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-04 00:00:00"))
    create_subscription(2, date2.date, 5, 0, fri_count: 1)

    date3 = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-05 00:00:00"))
    subscription3 = create_subscription(3, date3.date, 1, 1, sat_count: 1)
    UpdateRssServiceNew.init_subscription(subscription3, true, date3)

    now = ScheduleHelper::ScheduleDate.new(DateTime.parse("2022-05-06 00:00:00"))
    UpdateRssServiceNew.update_for_user(subscription1.user_id, now)

    actual_user_body = UserRss.find_by(user_id: subscription1.user.id).body
    # Sorted by publish date desc, sub date desc, post index desc
    expected_user_body = <<-BODY
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>FeedRewind</title>
    <link>https://feedrewind.herokuapp.com</link>
    <item>
      <title>Post 1</title>
      <link>https://blog2/1</link>
      <guid isPermaLink=\"false\">43974ed74066b207c30ffd0fed5146762e6c60745ac977004bc14507c7c42b50</guid>
      <description>from Test Subscription 2&lt;br&gt;&lt;br&gt;&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/2\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 2</title>
      <link>https://blog1/2</link>
      <guid isPermaLink=\"false\">37834f2f25762f23e1f74a531cbe445db73d6765ebe60878a7dfbecd7d4af6e1</guid>
      <description>from Test Subscription 1&lt;br&gt;&lt;br&gt;&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 1</title>
      <link>https://blog1/1</link>
      <guid isPermaLink=\"false\">16dc368a89b428b2485484313ba67a3912ca03f2b2b42429174a4f8b3dc84e44</guid>
      <description>from Test Subscription 1&lt;br&gt;&lt;br&gt;&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Fri, 06 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>You're all caught up with Test Subscription 3</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/3</link>
      <guid isPermaLink=\"false\">43b8e4fb7c0526d3ef514cac8554894843f36a7c0b3a5e3439f024fd5771cfd1</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/add\"&gt;Read something else?&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Post 1</title>
      <link>https://blog3/1</link>
      <guid isPermaLink=\"false\">c3ea99f86b2f8a74ef4145bb245155ff5f91cd856f287523481c15a1959d5fd1</guid>
      <description>from Test Subscription 3&lt;br&gt;&lt;br&gt;&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/3\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Test Subscription 3 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/3</link>
      <guid isPermaLink=\"false\">6b8620fd9d02c36e8581ecd6e56fe54122f2c7f58f3a8bc94b41551ee82f1693</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/3\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Thu, 05 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Test Subscription 2 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/2</link>
      <guid isPermaLink=\"false\">ebd09a71ff012c43b03f497b6551b9b41fe889ecc73aeceb2ab6c002bfbb6a91</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/2\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Wed, 04 May 2022 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Test Subscription 1 added to FeedRewind</title>
      <link>https://feedrewind.herokuapp.com/subscriptions/1</link>
      <guid isPermaLink=\"false\">02d00b67b9732798e803e344a5e57d80e3f7a620991f9cd5f2256ff8644de37a</guid>
      <description>&lt;a href=\"https://feedrewind.herokuapp.com/subscriptions/1\"&gt;Manage&lt;/a&gt;</description>
      <pubDate>Tue, 03 May 2022 00:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
    BODY
    assert_equal expected_user_body, actual_user_body
  end

  def create_subscription(
    id, finished_setup_at, total_count, published_count,
    mon_count: 0, tue_count: 0, wed_count: 0, thu_count: 0, fri_count: 0, sat_count: 0, sun_count: 0
  )
    blog = Blog.create!(
      name: "Test Blog #{id}",
      feed_url: "https://blog#{id}/feed.xml",
      status: "crawled_confirmed",
      status_updated_at: finished_setup_at,
      version: Blog::LATEST_VERSION,
      update_action: "recrawl"
    )
    blog.update_attribute(:id, id)

    subscription = Subscription.create!(
      user_id: "00000000-0000-0000-0000-000000000000",
      blog_id: id,
      name: "Test Subscription #{id}",
      status: "live",
      is_paused: false,
      is_added_past_midnight: false,
      version: 1,
      finished_setup_at: finished_setup_at
    )
    subscription.update_attribute(:id, id)

    subscription.schedules.create!(day_of_week: "mon", count: mon_count)
    subscription.schedules.create!(day_of_week: "tue", count: tue_count)
    subscription.schedules.create!(day_of_week: "wed", count: wed_count)
    subscription.schedules.create!(day_of_week: "thu", count: thu_count)
    subscription.schedules.create!(day_of_week: "fri", count: fri_count)
    subscription.schedules.create!(day_of_week: "sat", count: sat_count)
    subscription.schedules.create!(day_of_week: "sun", count: sun_count)

    (1..total_count).each do |index|
      post_id = id * 100 + index
      blog.blog_posts.create!(
        id: post_id,
        blog_id: id,
        index: index,
        url: "https://blog#{id}/#{index}",
        title: "Post #{index}"
      )
      subscription.subscription_posts.create!(
        id: post_id,
        blog_post_id: post_id,
        subscription_id: subscription.id,
        published_at: index <= published_count ? finished_setup_at : nil
      )
    end

    subscription
  end
end