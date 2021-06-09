def is_feed(page_content, logger)
  return false if page_content.nil?

  begin
    xml = Nokogiri::XML(page_content)
  rescue Nokogiri::XML::SyntaxError
    logger.log("Tried to parse as XML but looks malformed")
    return false
  end

  unless xml.xpath("/rss/channel").empty?
    return true
  end

  if xml.namespaces["xmlns"] == "http://www.w3.org/2005/Atom" && !xml.xpath("/xmlns:feed").empty?
    return true
  end

  false
end

FeedUrls = Struct.new(:root_url, :item_urls)

def extract_feed_urls(feed_content)
  xml = Nokogiri::XML(feed_content)
  rss_channels = xml.xpath("/rss/channel")
  if !rss_channels.empty?
    channel = rss_channels[0]

    root_url = channel.xpath("link")[0].inner_text
    raise "Couldn't extract root url from RSS" if root_url.nil?

    item_urls = channel.xpath("item").map do |item|
      links = item.xpath("link")
      unless links.empty?
        next links[0].inner_text
      end

      permalink_guids = item.xpath("guid").to_a.filter { |guid| guid.attributes["isPermaLink"].to_s == "true" }
      unless permalink_guids.empty?
        next permalink_guids[0].inner_text
      end

      nil
    end
    raise "Couldn't extract item urls from RSS" if item_urls.any?(&:nil?)

    FeedUrls.new(root_url, item_urls)
  else
    atom_feed = xml.xpath("/xmlns:feed")[0]

    root_url = get_atom_link(atom_feed)
    raise "Couldn't extract root url from Atom" if root_url.nil?

    entries = atom_feed.xpath("xmlns:entry")
    entry_urls = entries.map { |entry| get_atom_link(entry) }
    raise "Couldn't extract entry urls from Atom" if entry_urls.any?(&:nil?)

    FeedUrls.new(root_url, entry_urls)
  end
end

def get_atom_link(linkable)
  feed_links = linkable.xpath("xmlns:link")
  link_candidates = feed_links.to_a.filter { |link| link.attributes["rel"].to_s == 'alternate' }
  if link_candidates.empty?
    link_candidates = feed_links.to_a.filter { |link| link.attributes["rel"].nil? }
  end
  raise "Not one candidate link: #{link_candidates.length}" if link_candidates.length != 1

  link_candidates[0].attributes["href"].to_s
end
