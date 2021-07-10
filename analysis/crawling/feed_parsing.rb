require 'date'
require 'nokogumbo'
require 'set'
require_relative 'canonical_link'

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

FeedLinks = Struct.new(:root_link, :entry_links, :is_tumblr)

def extract_feed_links(feed_content, fetch_uri, host_redirect, logger)
  xml = Nokogiri::XML(feed_content)
  has_feedburner_namespace = xml.namespaces.key?("xmlns:feedburner")
  rss_channel = xml.at_xpath("/rss/channel")
  if rss_channel
    root_url = rss_channel.at_xpath("link")&.inner_text
    raise "Couldn't extract root url from RSS" if root_url.nil?

    item_nodes = rss_channel.xpath("item")
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

      if has_feedburner_namespace
        feedburner_orig_link = item.at_xpath("feedburner:origLink")
        if feedburner_orig_link
          next { pub_date: pub_date, url: feedburner_orig_link.inner_text }
        end
      end

      link = item.at_xpath("link")
      if link
        next { pub_date: pub_date, url: link.inner_text }
      end

      permalink_guid = item
        .xpath("guid")
        .to_a
        .filter { |guid| guid.attributes["isPermaLink"].to_s == "true" }
        .first
      if permalink_guid
        next { pub_date: pub_date, url: permalink_guid.inner_text }
      end

      nil
    end
    raise "Couldn't extract item urls from RSS" if items.any?(&:nil?)

    sorted_items = try_sort_reverse_chronological(items, logger)
    entry_urls = sorted_items.map { |item| item[:url] }

    generator_node = rss_channel.at_xpath("generator")
    is_tumblr = generator_node && generator_node.inner_text.downcase.start_with?("tumblr")
  else
    atom_feed = xml.at_xpath("/xmlns:feed")
    root_url = get_atom_link(atom_feed, false)

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

      link = get_atom_link(entry, has_feedburner_namespace)

      if link
        { pub_date: published_date, url: link }
      end
    end
    raise "Couldn't extract entry urls from Atom" if entries.any?(&:nil?)

    sorted_entries = try_sort_reverse_chronological(entries, logger)
    entry_urls = sorted_entries.map { |entry| entry[:url] }
    is_tumblr = false
  end
  root_link = root_url ? to_canonical_link(root_url, logger, fetch_uri) : nil
  entry_links = entry_urls.map { |entry_url| entry_url ? to_canonical_link(entry_url, logger, fetch_uri) : nil }

  entry_links.map! do |entry_link|
    case entry_link.uri.host
    when host_redirect.redirect_from_host
      entry_link.uri.host = host_redirect.redirect_to_host
      to_canonical_link(entry_link.uri.to_s, logger)
    when host_redirect.weird_feed_host
      raise "Entry points to the same host as feed but feed is third party: #{entry_link.url} (#{host_redirect.weird_feed_host})"
    else
      entry_link
    end
  end

  FeedLinks.new(root_link, entry_links, is_tumblr)
end

def finalize_feed_links(possible_redirect_feed_links, entry_to_host, logger)
  final_entry_links = possible_redirect_feed_links.entry_links.map do |entry_link|
    entry_link.uri.host = entry_to_host
    to_canonical_link(entry_link.uri.to_s, logger)
  end
  FeedLinks.new(possible_redirect_feed_links.root_link, final_entry_links)
end

def get_atom_link(linkable, has_feedburner_namespace)
  if has_feedburner_namespace
    feedburner_orig_link = linkable.at_xpath("feedburner:origLink")
    if feedburner_orig_link
      return feedburner_orig_link.inner_text
    end
  end

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