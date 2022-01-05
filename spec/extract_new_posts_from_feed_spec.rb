require 'rspec/expectations'
require 'uri'
require_relative '../analysis/crawling/logger'
require_relative '../app/lib/guided_crawling/extract_new_posts_from_feed'

RSpec::Matchers.define :match_urls_titles do |expected_urls, expected_titles|
  match do |new_links|
    return false unless new_links.length == expected_urls.length
    return false unless new_links.length == expected_titles.length

    new_links.zip(expected_urls, expected_titles).each do |new_link, url, title|
      return false unless new_link.url == url
      return false unless new_link.title.value == title
    end

    true
  end
end

RSpec.describe "extract_new_posts_from_feed" do
  logger = MyLogger.new($stdout)

  def create_feed(urls, titles)
    "<rss><channel>" +
      urls
        .zip(titles)
        .map { |url, title| "<item><link>#{url}</link><title>#{title}</title></item>" }
        .join("") +
      "</channel></rss>"
  end

  feed_uri = URI("https://blog/feed")
  curi_eq_cfg = CanonicalEqualityConfig.new(Set.new, false)

  it "should handle feed without updates" do
    existing_post_urls = %w[https://blog/post1 https://blog/post2 https://blog/post3]
    feed_content = create_feed(
      existing_post_urls,
      %w[post1 post2 post3]
    )
    expect(extract_new_posts_from_feed(feed_content, feed_uri, existing_post_urls, curi_eq_cfg, logger))
      .to eq []
  end

  it "should bail on feed with too many updates" do
    feed_content = create_feed(
      %w[https://blog/post1 https://blog/post2 https://blog/post3 https://blog/post4],
      %w[post1 post2 post3 post4]
    )
    existing_post_urls = %w[https://blog/post3 https://blog/post4 https://blog/post5]
    expect(extract_new_posts_from_feed(feed_content, feed_uri, existing_post_urls, curi_eq_cfg, logger))
      .to be_nil
  end

  it "should bail on feed with drastic changes" do
    feed_content = create_feed(
      %w[https://blog/post4 https://blog/post3 https://blog/post2 https://blog/post1],
      %w[post4 post3 post2 post1]
    )
    existing_post_urls = %w[https://blog/post2 https://blog/post3 https://blog/post4 https://blog/post5]
    expect(extract_new_posts_from_feed(feed_content, feed_uri, existing_post_urls, curi_eq_cfg, logger))
      .to be_nil
  end

  it "should bail on shuffled feed with matching suffix" do
    feed_content = create_feed(
      %w[https://blog/post5 https://blog/post1 https://blog/post2 https://blog/post3 https://blog/post4],
      %w[post5 post1 post2 post3 post4]
    )
    existing_post_urls = %w[https://blog/post2 https://blog/post3 https://blog/post4 https://blog/post5]
    expect(extract_new_posts_from_feed(feed_content, feed_uri, existing_post_urls, curi_eq_cfg, logger))
      .to be_nil
  end

  it "should bail on feed with duplicate dates for new posts" do
    feed_content = %{
      <rss>
        <channel>
          <item>
            <pubDate>Sun, 21 Oct 2015 09:04:05 GMT</pubDate>
            <link>https://blog/post1</link>
            <title>post1</title>
          </item>
          <item>
            <pubDate>Wed, 21 Oct 2015 08:28:48 GMT</pubDate>
            <link>https://blog/post2</link>
            <title>post2</title>
          </item>
          <item>
            <pubDate>Wed, 21 Oct 2014 08:28:48 GMT</pubDate>
            <link>https://blog/post3</link>
            <title>post3</title>
          </item>
          <item>
            <pubDate>Wed, 21 Oct 2013 08:28:48 GMT</pubDate>
            <link>https://blog/post4</link>
            <title>post4</title>
          </item>
          <item>
            <pubDate>Wed, 21 Oct 2012 08:28:48 GMT</pubDate>
            <link>https://blog/post5</link>
            <title>post5</title>
          </item>
        </channel>
      </rss>
    }
    existing_post_urls = %w[https://blog/post3 https://blog/post4 https://blog/post5]
    expect(extract_new_posts_from_feed(feed_content, feed_uri, existing_post_urls, curi_eq_cfg, logger))
      .to be_nil
  end

  it "should handle feed with duplicate dates for the oldest new post and the newest old post" do
    feed_content = %{
      <rss>
        <channel>
          <item>
            <pubDate>Sun, 21 Oct 2016 09:04:05 GMT</pubDate>
            <link>https://blog/post1</link>
            <title>post1</title>
          </item>
          <item>
            <pubDate>Wed, 21 Oct 2014 09:04:05 GMT</pubDate>
            <link>https://blog/post2</link>
            <title>post2</title>
          </item>
          <item>
            <pubDate>Wed, 21 Oct 2014 08:28:48 GMT</pubDate>
            <link>https://blog/post3</link>
            <title>post3</title>
          </item>
          <item>
            <pubDate>Wed, 21 Oct 2013 08:28:48 GMT</pubDate>
            <link>https://blog/post4</link>
            <title>post4</title>
          </item>
          <item>
            <pubDate>Wed, 21 Oct 2012 08:28:48 GMT</pubDate>
            <link>https://blog/post5</link>
            <title>post5</title>
          </item>
        </channel>
      </rss>
    }
    existing_post_urls = %w[https://blog/post3 https://blog/post4 https://blog/post5]
    expect(extract_new_posts_from_feed(feed_content, feed_uri, existing_post_urls, curi_eq_cfg, logger))
      .to match_urls_titles(%w[https://blog/post1 https://blog/post2], %w[post1 post2])
  end

  it "should handle feed with duplicate dates for the old posts" do
    feed_content = %{
      <rss>
        <channel>
          <item>
            <pubDate>Sun, 21 Oct 2016 09:04:05 GMT</pubDate>
            <link>https://blog/post1</link>
            <title>post1</title>
          </item>
          <item>
            <pubDate>Wed, 21 Oct 2015 09:04:05 GMT</pubDate>
            <link>https://blog/post2</link>
            <title>post2</title>
          </item>
          <item>
            <pubDate>Wed, 21 Oct 2014 09:04:05 GMT</pubDate>
            <link>https://blog/post3</link>
            <title>post3</title>
          </item>
          <item>
            <pubDate>Wed, 21 Oct 2014 08:28:48 GMT</pubDate>
            <link>https://blog/post4</link>
            <title>post4</title>
          </item>
          <item>
            <pubDate>Wed, 21 Oct 2012 08:28:48 GMT</pubDate>
            <link>https://blog/post5</link>
            <title>post5</title>
          </item>
        </channel>
      </rss>
    }
    existing_post_urls = %w[https://blog/post3 https://blog/post4 https://blog/post5]
    expect(extract_new_posts_from_feed(feed_content, feed_uri, existing_post_urls, curi_eq_cfg, logger))
      .to match_urls_titles(%w[https://blog/post1 https://blog/post2], %w[post1 post2])
  end

  it "should handle feed with good updates" do
    feed_content = create_feed(
      %w[https://blog/post1 https://blog/post2 https://blog/post3 https://blog/post4 https://blog/post5 https://blog/post6],
      %w[post1 post2 post3 post4 post5 post6]
    )
    existing_post_urls = %w[https://blog/post4 https://blog/post5 https://blog/post6]
    expect(extract_new_posts_from_feed(feed_content, feed_uri, existing_post_urls, curi_eq_cfg, logger))
      .to match_urls_titles(
            %w[https://blog/post1 https://blog/post2 https://blog/post3], %w[post1 post2 post3]
          )
  end
end
