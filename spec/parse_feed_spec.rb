require 'rspec/expectations'
require_relative '../analysis/crawling/logger'
require_relative '../app/lib/guided_crawling/feed_parsing'

RSpec::Matchers.define :match_feed_links do |expected_root_url, expected_entry_urls|
  match do |actual_feed_links|
    expected_entry_curis = expected_entry_urls.map { |url| CanonicalUri.from_db_string(url) }

    actual_feed_links.root_link&.url == expected_root_url &&
      actual_feed_links
        .entry_links
        .sequence_match(expected_entry_curis, CanonicalEqualityConfig.new(Set.new, false))
  end
end

RSpec.describe "extract_feed_links" do
  logger = MyLogger.new($stdout)

  it "should parse RSS feeds" do
    rss_content = %{
      <rss>
        <channel>
          <link>https://root</link>
          <item>
            <link>https://root/a</link>
          </item>
          <item>
            <link>https://root/b</link>
          </item>
        </channel>
      </rss>
    }
    expect(parse_feed(rss_content, "https://root/feed", logger))
      .to match_feed_links("https://root", %w[root/a root/b])
  end

  it "should parse urls from RSS guid permalinks" do
    rss_content = %{
      <rss>
        <channel>
          <link>https://root</link>
          <item>
            <guid isPermaLink="true">https://root/a</link>
          </item>
          <item>
            <guid isPermaLink="true">https://root/b</link>
          </item>
        </channel>
      </rss>
    }
    expect(parse_feed(rss_content, "https://root/feed", logger))
      .to match_feed_links("https://root", %w[root/a root/b])
  end

  it "should parse RSS if channel url is not present" do
    rss_content = %{
      <rss>
        <channel>
        </channel>
      </rss>
    }
    expect(parse_feed(rss_content, "https://root/feed", logger).root_link)
      .to be_nil
  end

  it "should fail RSS parsing if item url is not present" do
    rss_content = %{
      <rss>
        <channel>
          <link>https://root</link>
          <item>
            <link>https://root/a</link>
          </item>
          <item>
          </item>
        </channel>
      </rss>
    }
    expect { parse_feed(rss_content, "https://root/feed", logger) }
      .to raise_error(/Couldn't extract item urls from RSS/)
  end

  it "should reverse RSS items if they are chronological" do
    rss_content = %{
      <rss>
        <channel>
          <link>https://root</link>
          <item>
            <pubDate>Wed, 21 Oct 2015 08:28:48 GMT</pubDate>
            <link>https://root/a</link>
          </item>
          <item>
            <pubDate>Sun, 25 Oct 2015 05:04:05 GMT</pubDate>
            <link>https://root/b</link>
          </item>
        </channel>
      </rss>
    }
    expect(parse_feed(rss_content, "https://root/feed", logger))
      .to match_feed_links("https://root", %w[root/b root/a])
  end

  it "should sort RSS items if dates are shuffled and unique" do
    rss_content = %{
      <rss>
        <channel>
          <link>https://root</link>
          <item>
            <pubDate>Wed, 21 Oct 2015 08:28:48 GMT</pubDate>
            <link>https://root/a</link>
          </item>
          <item>
            <pubDate>Sun, 25 Oct 2015 05:04:05 GMT</pubDate>
            <link>https://root/b</link>
          </item>
          <item>
            <pubDate>Sun, 20 Oct 2015 05:04:05 GMT</pubDate>
            <link>https://root/c</link>
          </item>
        </channel>
      </rss>
    }
    expect(parse_feed(rss_content, "https://root/feed", logger))
      .to match_feed_links("https://root", %w[root/b root/a root/c])
  end

  it "should sort RSS items if dates are shuffled and repeating" do
    rss_content = %{
      <rss>
        <channel>
          <link>https://root</link>
          <item>
            <pubDate>Wed, 20 Oct 2015 05:04:05 GMT</pubDate>
            <link>https://root/a</link>
          </item>
          <item>
            <pubDate>Sun, 25 Oct 2015 05:04:05 GMT</pubDate>
            <link>https://root/b</link>
          </item>
          <item>
            <pubDate>Sun, 20 Oct 2015 05:04:05 GMT</pubDate>
            <link>https://root/c</link>
          </item>
        </channel>
      </rss>
    }
    expect(parse_feed(rss_content, "https://root/feed", logger))
      .to match_feed_links("https://root", %w[root/b root/a root/c])
            .and match_feed_links("https://root", %w[root/b root/c root/a])
  end

  it "should sort RSS items by dates but not timestamps" do
    rss_content = %{
      <rss>
        <channel>
          <link>https://root</link>
          <item>
            <pubDate>Wed, 20 Oct 2015 05:04:06 GMT</pubDate>
            <link>https://root/a</link>
          </item>
          <item>
            <pubDate>Sun, 20 Oct 2015 05:04:05 GMT</pubDate>
            <link>https://root/b</link>
          </item>
        </channel>
      </rss>
    }
    expect(parse_feed(rss_content, "https://root/feed", logger))
      .to match_feed_links("https://root", %w[root/a root/b])
            .and match_feed_links("https://root", %w[root/b root/a])
  end

  it "should parse RSS if a date is invalid" do
    rss_content = %{
      <rss>
        <channel>
          <link>https://root</link>
          <item>
            <pubDate>asdf</pubDate>
            <link>https://root/a</link>
          </item>
        </channel>
      </rss>
    }
    expect(parse_feed(rss_content, "https://root/feed", logger))
      .to match_feed_links("https://root", %w[root/a])
  end

  it "should prioritize feedburner orig links in RSS" do
    rss_content = %{
      <rss xmlns:feedburner="http://rssnamespace.org/feedburner/ext/1.0">
        <channel>
          <link>https://root</link>
          <item>
            <link>https://feedburner/a</link>
            <feedburner:origLink>https://root/a</feedburner:origLink>
          </item>
          <item>
            <link>https://feedburner/b</link>
            <feedburner:origLink>https://root/b</feedburner:origLink>
          </item>
        </channel>
      </rss>
    }
    expect(parse_feed(rss_content, "https://root/feed", logger))
      .to match_feed_links("https://root", %w[root/a root/b])
  end

  it "should recognize Tumblr RSS generator" do
    rss_content = %{
      <rss>
        <channel>
          <link>https://root</link>
          <generator>Tumblr (3.0; @webcomicname)</generator>
          <item>
            <link>https://root/a</link>
          </item>
          <item>
            <link>https://root/b</link>
          </item>
        </channel>
      </rss>
    }
    expect(parse_feed(rss_content, "https://root/feed", logger).generator)
      .to eq :tumblr
  end

  it "should recognize Blogger RSS generator" do
    rss_content = %{
      <rss>
        <channel>
          <link>https://root</link>
          <generator>Blogger</generator>
          <item>
            <link>https://root/a</link>
          </item>
          <item>
            <link>https://root/b</link>
          </item>
        </channel>
      </rss>
    }
    expect(parse_feed(rss_content, "https://root/feed", logger).generator)
      .to eq :blogger
  end

  it "should recognize Medium RSS generator" do
    rss_content = %{
      <rss xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:atom="http://www.w3.org/2005/Atom" xmlns:cc="http://cyber.law.harvard.edu/rss/creativeCommonsRssModule.html" version="2.0">
        <channel>
          <link>https://root</link>
          <generator>Medium</generator>
          <item>
            <link>https://root/a</link>
          </item>
          <item>
            <link>https://root/b</link>
          </item>
        </channel>
      </rss>
    }
    expect(parse_feed(rss_content, "https://root/feed", logger).generator)
      .to eq :medium
  end

  it "should parse Atom feeds" do
    atom_content = %{
      <feed xmlns="http://www.w3.org/2005/Atom">
        <link rel="alternate" href="https://root"/>
        <entry>
          <link rel="alternate" href="https://root/a"/>
        </entry>
        <entry>
          <link rel="alternate" href="https://root/b"/>
        </entry>
      </feed>
    }
    expect(parse_feed(atom_content, "https://root/feed", logger))
      .to match_feed_links("https://root", %w[root/a root/b])
  end

  it "should parse Atom links without rel" do
    atom_content = %{
      <feed xmlns="http://www.w3.org/2005/Atom">
        <link href="https://root"/>
        <entry>
          <link href="https://root/a"/>
        </entry>
        <entry>
          <link href="https://root/b"/>
        </entry>
      </feed>
    }
    expect(parse_feed(atom_content, "https://root/feed", logger))
      .to match_feed_links("https://root", %w[root/a root/b])
  end

  it "should parse Atom if channel url is not present" do
    atom_content = %{
      <feed xmlns="http://www.w3.org/2005/Atom">
          <link/>
      </feed>
    }
    expect(parse_feed(atom_content, "https://root/feed", logger))
      .to match_feed_links(nil, [])
  end

  it "should parse Atom if channel link is not present" do
    atom_content = %{
      <feed xmlns="http://www.w3.org/2005/Atom">
      </feed>
    }
    expect(parse_feed(atom_content, "https://root/feed", logger))
      .to match_feed_links(nil, [])
  end

  it "should fail Atom parsing if item url is not present" do
    atom_content = %{
      <feed xmlns="http://www.w3.org/2005/Atom">
        <link href="https://root"/>
        <entry>
          <link href="https://root/a"/>
        </entry>
        <entry>
          <link/>
        </entry>
      </feed>
    }
    expect { parse_feed(atom_content, "https://root/feed", logger) }
      .to raise_error(/Couldn't extract entry urls from Atom/)
  end

  it "should fail Atom parsing if item link is not present" do
    atom_content = %{
      <feed xmlns="http://www.w3.org/2005/Atom">
        <link href="https://root"/>
        <entry>
          <link href="https://root/a"/>
        </entry>
        <entry>
        </entry>
      </feed>
    }
    expect { parse_feed(atom_content, "https://root/feed", logger) }
      .to raise_error(/Couldn't extract entry urls from Atom/)
  end

  it "should reverse Atom items if they are chronological" do
    atom_content = %{
      <feed xmlns="http://www.w3.org/2005/Atom">
        <link href="https://root"/>
        <entry>
          <published>2020-05-16T00:00:00-04:00</published>
          <link href="https://root/a"/>
        </entry>
        <entry>
          <published>2021-05-16T00:00:00-04:00</published>
          <link href="https://root/b"/>
        </entry>
      </feed>
    }
    expect(parse_feed(atom_content, "https://root/feed", logger))
      .to match_feed_links("https://root", %w[root/b root/a])
  end

  it "should sort Atom items if dates are shuffled and unique" do
    atom_content = %{
      <feed xmlns="http://www.w3.org/2005/Atom">
        <link href="https://root"/>
        <entry>
          <published>2020-05-16T00:00:00-04:00</published>
          <link href="https://root/a"/>
        </entry>
        <entry>
          <published>2021-05-16T00:00:00-04:00</published>
          <link href="https://root/b"/>
        </entry>
        <entry>
          <published>2019-05-16T00:00:00-04:00</published>
          <link href="https://root/c"/>
        </entry>
      </feed>
    }
    expect(parse_feed(atom_content, "https://root/feed", logger))
      .to match_feed_links("https://root", %w[root/b root/a root/c])
  end

  it "should sort Atom items if dates are shuffled and repeating" do
    atom_content = %{
      <feed xmlns="http://www.w3.org/2005/Atom">
        <link href="https://root"/>
        <entry>
          <published>2019-05-16T00:00:00-04:00</published>
          <link href="https://root/a"/>
        </entry>
        <entry>
          <published>2021-05-16T00:00:00-04:00</published>
          <link href="https://root/b"/>
        </entry>
        <entry>
          <published>2019-05-16T00:00:00-04:00</published>
          <link href="https://root/c"/>
        </entry>
      </feed>
    }
    expect(parse_feed(atom_content, "https://root/feed", logger))
      .to match_feed_links("https://root", %w[root/b root/a root/c])
            .and match_feed_links("https://root", %w[root/b root/c root/a])
  end

  it "should sort Atom items by dates but not timestamps" do
    atom_content = %{
      <feed xmlns="http://www.w3.org/2005/Atom">
        <link href="https://root"/>
        <entry>
          <published>2019-05-16T00:00:01-04:00</published>
          <link href="https://root/a"/>
        </entry>
        <entry>
          <published>2019-05-16T00:00:00-04:00</published>
          <link href="https://root/b"/>
        </entry>
      </feed>
    }
    expect(parse_feed(atom_content, "https://root/feed", logger))
      .to match_feed_links("https://root", %w[root/b root/a])
            .and match_feed_links("https://root", %w[root/a root/b])
  end

  it "should parse Atom if a date is invalid" do
    atom_content = %{
      <feed xmlns="http://www.w3.org/2005/Atom">
        <link href="https://root"/>
        <entry>
          <published>asdf</published>
          <link href="https://root/a"/>
        </entry>
      </feed>
    }
    expect(parse_feed(atom_content, "https://root/feed", logger))
      .to match_feed_links("https://root", %w[root/a])
  end

  it "should prioritize feedburner orig links in Atom" do
    atom_content = %{
      <feed xmlns="http://www.w3.org/2005/Atom" xmlns:feedburner="http://rssnamespace.org/feedburner/ext/1.0">
        <link rel="alternate" href="https://root"/>
        <entry>
          <link rel="alternate" href="https://feedburner/a"/>
          <feedburner:origLink>https://root/a</feedburner:origLink>
        </entry>
        <entry>
          <link rel="alternate" href="https://feedburner/b"/>
          <feedburner:origLink>https://root/b</feedburner:origLink>
        </entry>
      </feed>
    }
    expect(parse_feed(atom_content, "https://root/feed", logger))
      .to match_feed_links("https://root", %w[root/a root/b])
  end

  it "should recognize Blogger Atom generator" do
    atom_content = %{
      <feed xmlns="http://www.w3.org/2005/Atom">
        <link rel="alternate" href="https://root"/>
        <generator version='7.00' uri='http://www.blogger.com'>Blogger</generator>
        <entry>
          <link rel="alternate" href="https://root/a"/>
        </entry>
        <entry>
          <link rel="alternate" href="https://root/b"/>
        </entry>
      </feed>
    }
    expect(parse_feed(atom_content, "https://root/feed", logger).generator)
      .to eq :blogger
  end
end