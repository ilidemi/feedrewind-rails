require 'date'
require 'nokogumbo'
require 'set'

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

def extract_feed_urls(feed_content, logger)
  xml = Nokogiri::XML(feed_content)
  rss_channels = xml.xpath("/rss/channel")
  if !rss_channels.empty?
    channel = rss_channels[0]

    root_url = channel.xpath("link")[0]&.inner_text
    raise "Couldn't extract root url from RSS" if root_url.nil?

    item_nodes = channel.xpath("item")
    items = item_nodes.map do |item|
      pub_dates = item.xpath("pubDate")
      if pub_dates.length == 1
        begin
          pub_date = DateTime.rfc822(pub_dates[0].inner_text)
        rescue Date::Error
          logger.log("Invalid pubDate: #{pub_dates[0].inner_text}")
          pub_date = nil
        end
      else
        pub_date = nil
      end

      links = item.xpath("link")
      unless links.empty?
        next { pub_date: pub_date, url: links[0].inner_text }
      end

      permalink_guids = item.xpath("guid").to_a.filter { |guid| guid.attributes["isPermaLink"].to_s == "true" }
      unless permalink_guids.empty?
        next { pub_date: pub_date, url: permalink_guids[0].inner_text }
      end

      nil
    end
    raise "Couldn't extract item urls from RSS" if items.any?(&:nil?)

    sorted_items = try_sort_reverse_chronological(items, logger)
    item_urls = sorted_items.map { |item| item[:url] }
    FeedUrls.new(root_url, item_urls)
  else
    atom_feed = xml.xpath("/xmlns:feed")[0]
    root_url = get_atom_link(atom_feed)

    entry_nodes = atom_feed.xpath("xmlns:entry")
    entries = entry_nodes.map do |entry|
      published_dates = entry.xpath("xmlns:published")
      if published_dates.length == 0
        published_dates = entry.xpath("xmlns:updated")
      end

      if published_dates.length == 1
        begin
          published_date = DateTime.iso8601(published_dates[0].inner_text)
        rescue Date::Error
          logger.log("Invalid published: #{published_dates[0].inner_text}")
          published_date = nil
        end
      else
        published_date = nil
      end

      link = get_atom_link(entry)

      if link
        { pub_date: published_date, url: link }
      end
    end
    raise "Couldn't extract entry urls from Atom" if entries.any?(&:nil?)

    sorted_entries = try_sort_reverse_chronological(entries, logger)
    entry_urls = sorted_entries.map { |entry| entry[:url] }
    FeedUrls.new(root_url, entry_urls)
  end
end

def get_atom_link(linkable)
  feed_links = linkable.xpath("xmlns:link")
  link_candidates = feed_links.to_a.filter { |link| link.attributes["rel"].to_s == 'alternate' }
  if link_candidates.empty?
    link_candidates = feed_links.to_a.filter { |link| link.attributes["rel"].nil? }
  end
  return nil if link_candidates.empty?
  raise "Not one candidate link: #{link_candidates.length}" if link_candidates.length != 1

  link_candidates[0].attributes["href"]&.to_s
end

def try_sort_reverse_chronological(items, logger)
  if items.any? { |item| item[:pub_date].nil? }
    return items
  end

  if items.length < 2
    return items
  end

  all_dates_equal = true
  are_dates_ascending_order = true
  are_dates_descending_order = true
  item_dates = items.map { |item| item[:pub_date] }
  item_dates.each_cons(2) do |pub_date1, pub_date2|
    if pub_date1 != pub_date2
      all_dates_equal = false
    end
    if pub_date1 < pub_date2
      are_dates_descending_order = false
    end
    if pub_date1 > pub_date2
      are_dates_ascending_order = false
    end
  end

  are_dates_duplicate = item_dates.to_set.length != item_dates.length

  if all_dates_equal
    logger.log("All item dates are equal")
  end

  if !are_dates_ascending_order && !are_dates_descending_order
    if are_dates_duplicate
      logger.log("Item dates are shuffled but there are also duplicates")
    else
      logger.log("Item dates are shuffled but no duplicates, sorting")
      return items
        .sort_by { |item| item[:pub_date] }
        .reverse
    end
  end

  if are_dates_ascending_order
    items.reverse
  else
    items
  end
end