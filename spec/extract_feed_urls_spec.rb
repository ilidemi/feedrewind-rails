require_relative '../analysis/crawling/feed_parsing'
require_relative '../analysis/crawling/logger'

RSpec.describe "extract_feed_links" do
  logger = MyLogger.new($stdout)

  def feed_links(root_url, entry_urls, logger)
    FeedLinks.new(
      root_url ? to_canonical_link(root_url, logger) : nil,
      entry_urls.map { |url| url ? to_canonical_link(url, logger) : nil }
    )
  end

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
    expect(extract_feed_links(rss_content, "https://root/feed", logger))
      .to eq feed_links("https://root", %w[https://root/a https://root/b], logger)
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
    expect(extract_feed_links(rss_content, "https://root/feed", logger))
      .to eq feed_links("https://root", %w[https://root/a https://root/b], logger)
  end

  it "should fail RSS parsing if channel url is not present" do
    rss_content = %{
      <rss>
        <channel>
        </channel>
      </rss>
    }
    expect { extract_feed_links(rss_content, "https://root/feed", logger) }
      .to raise_error(/Couldn't extract root url from RSS/)
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
    expect { extract_feed_links(rss_content, "https://root/feed", logger) }
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
    expect(extract_feed_links(rss_content, "https://root/feed", logger))
      .to eq feed_links("https://root", %w[https://root/b https://root/a], logger)
  end

  it "should sort RSS items if dates are shuffled but unique" do
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
    expect(extract_feed_links(rss_content, "https://root/feed", logger))
      .to eq feed_links("https://root", %w[https://root/b https://root/a https://root/c], logger)
  end

  it "should preserve RSS order if dates are shuffled but repeating" do
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
    expect(extract_feed_links(rss_content, "https://root/feed", logger))
      .to eq feed_links("https://root", %w[https://root/a https://root/b https://root/c], logger)
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
    expect(extract_feed_links(rss_content, "https://root/feed", logger))
      .to eq feed_links("https://root", %w[https://root/a], logger)
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
    expect(extract_feed_links(rss_content, "https://root/feed", logger))
      .to eq feed_links("https://root", %w[https://root/a https://root/b], logger)
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
    expect(extract_feed_links(atom_content, "https://root/feed", logger))
      .to eq feed_links("https://root", %w[https://root/a https://root/b], logger)
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
    expect(extract_feed_links(atom_content, "https://root/feed", logger))
      .to eq feed_links("https://root", %w[https://root/a https://root/b], logger)
  end

  it "should parse Atom if channel url is not present" do
    atom_content = %{
      <feed xmlns="http://www.w3.org/2005/Atom">
          <link/>
      </feed>
    }
    expect(extract_feed_links(atom_content, "https://root/feed", logger))
      .to eq feed_links(nil, [], logger)
  end

  it "should parse Atom if channel link is not present" do
    atom_content = %{
      <feed xmlns="http://www.w3.org/2005/Atom">
      </feed>
    }
    expect(extract_feed_links(atom_content, "https://root/feed", logger))
      .to eq feed_links(nil, [], logger)
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
    expect { extract_feed_links(atom_content, "https://root/feed", logger) }
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
    expect { extract_feed_links(atom_content, "https://root/feed", logger) }
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
    expect(extract_feed_links(atom_content, "https://root/feed", logger))
      .to eq feed_links("https://root", %w[https://root/b https://root/a], logger)
  end

  it "should sort Atom items if dates are shuffled but unique" do
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
    expect(extract_feed_links(atom_content, "https://root/feed", logger))
      .to eq feed_links("https://root", %w[https://root/b https://root/a https://root/c], logger)
  end

  it "should preserve Atom items order if dates are shuffled and have duplicates" do
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
    expect(extract_feed_links(atom_content, "https://root/feed", logger))
      .to eq feed_links("https://root", %w[https://root/a https://root/b https://root/c], logger)
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
    expect(extract_feed_links(atom_content, "https://root/feed", logger))
      .to eq feed_links("https://root", %w[https://root/a], logger)
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
    expect(extract_feed_links(atom_content, "https://root/feed", logger))
      .to eq feed_links("https://root", %w[https://root/a https://root/b], logger)
  end
end