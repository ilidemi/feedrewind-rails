require 'nokogumbo'
require_relative 'crawling'
require_relative 'db'
require_relative 'historical_common'

def try_extract_paged(
  page, page_links, page_urls_set, feed_item_urls, feed_item_urls_set, best_count, subpattern_priorities,
  start_link_id, redirects, db, logger
)
  min_page_items = 3
  page_overlapping_links_count = nil
  feed_item_urls.each_with_index do |feed_item_url, index|
    if index == feed_item_urls.length - 1 && page_urls_set.include?(feed_item_url)
      page_overlapping_links_count = feed_item_urls.length
    elsif !page_urls_set.include?(feed_item_url)
      if index >= min_page_items
        page_overlapping_links_count = index
      else
        return nil
      end
    end
  end

  page2_url_regex = make_page_url_regex(2)
  links_to_page2 = page_links.filter do |page_link|
    page_link[:host] == page[:fetch_uri].host && page2_url_regex.match?(page_link[:canonical_url])
  end
  return nil if links_to_page2.empty?

  if links_to_page2.map { |page2_link| page2_link[:canonical_url] }.to_set.length > 1
    logger.log("Page #{page[:canonical_url]} has multiple page 2 links: #{links_to_page2}")
    return nil
  end
  link_to_page2 = links_to_page2.first

  logger.log("Possible page 1: #{page[:canonical_url]} (#{page_overlapping_links_count} overlaps)")

  get_masked_xpaths_func = method(:get_single_masked_xpaths)
  links_by_masked_xpath = group_links_by_masked_xpath(
    page_links, feed_item_urls_set, :xpath, get_masked_xpaths_func
  )

  page_size_masked_xpaths = []
  links_by_masked_xpath.each do |masked_xpath, masked_xpath_links|
    next if masked_xpath_links.length < min_page_items

    masked_xpath_link_urls = masked_xpath_links.map { |link| link[:canonical_url] }
    feed_overlap_length = [masked_xpath_link_urls.length, feed_item_urls.length].min
    next unless masked_xpath_link_urls[0...feed_overlap_length] == feed_item_urls[0...feed_overlap_length]

    masked_xpath_link_urls_set = masked_xpath_link_urls.to_set
    if masked_xpath_link_urls_set.length != masked_xpath_link_urls.length
      logger.log("Masked xpath #{masked_xpath} has duplicates: #{masked_xpath_link_urls}")
      next
    end

    page_size_masked_xpaths << [masked_xpath_link_urls.length, masked_xpath]
  end

  if page_size_masked_xpaths.empty?
    logger.log("No good overlap with feed prefix")
    return nil
  end

  page_size_masked_xpaths_sorted = page_size_masked_xpaths
    .sort_by { |xpath_page_size, _| -xpath_page_size }
  logger.log("Max prefix: #{page_size_masked_xpaths.first[0]}")

  page2 = fetch_page(start_link_id, link_to_page2[:canonical_url], db)
  if page2.nil?
    logger.log("Page 2 not found in db: #{link_to_page2[:canonical_url]}")
    return nil
  end
  page2_doc = Nokogiri::HTML5(page2[:content])

  page2_classes_by_xpath = {}
  page1_entry_links = nil
  page2_entry_links = nil
  good_masked_xpath = nil
  page_size = nil
  remaining_feed_item_urls = nil

  page_size_masked_xpaths_sorted.each do |xpath_page_size, masked_xpath|
    page2_xpath_link_elements = page2_doc.xpath(masked_xpath)
    page2_xpath_links = page2_xpath_link_elements.filter_map do |element|
      html_element_to_link(
        element, page2[:fetch_uri], page2_doc, page2_classes_by_xpath, redirects, logger, true, false
      )
    end
    next if page2_xpath_links.empty?

    page1_xpath_links = links_by_masked_xpath[masked_xpath]
    page1_xpath_urls_set = page1_xpath_links
      .map { |link| link[:canonical_url] }
      .to_set
    next if page2_xpath_links.any? do |page2_xpath_link|
      page1_xpath_urls_set.include?(page2_xpath_link[:canonical_url])
    end
    next if page2_xpath_links.length > page1_xpath_links.length

    page2_xpath_urls = page2_xpath_links.map { |link| link[:canonical_url] }
    page2_feed_item_urls = feed_item_urls[xpath_page_size..-1] || []
    feed_overlap_length = [page2_xpath_urls.length, page2_feed_item_urls.length].min
    next unless page2_xpath_urls[0...feed_overlap_length] == page2_feed_item_urls[0...feed_overlap_length]

    page1_entry_links = page1_xpath_links
    page2_entry_links = page2_xpath_links
    good_masked_xpath = masked_xpath
    page_size = xpath_page_size
    remaining_feed_item_urls = page2_feed_item_urls[page2_entry_links.length...-1] || []
    logger.log("Possible page 2: #{link_to_page2[:canonical_url]}")
    logger.log("XPath looks good for page 2: #{masked_xpath} (#{page1_entry_links.length} + #{page2_entry_links.length} links)")
    break
  end

  if page2_entry_links.nil?
    logger.log("Couldn't find an xpath matching page 1 and page 2")
    return nil
  end

  page2_links = extract_links(page2, [page2[:fetch_uri].host], redirects, logger, true, false)[:allowed_host_links]
  page3_url_regex = make_page_url_regex(3)
  links_to_page3 = page2_links.filter { |page2_link| page3_url_regex.match?(page2_link[:canonical_url]) }

  if links_to_page3.map { |page3_link| page3_link[:canonical_url] }.to_set.length > 1
    logger.log("Page 2 #{page2[:canonical_url]} has multiple page 3 links: #{links_to_page3}")
    return nil
  end

  link_to_page3 = links_to_page3.first
  if link_to_page3 && page2_entry_links.length != page_size
    logger.log("There are at least 3 pages and page 2 size (#{page2_entry_links.length}) is not equal to expected page size (#{page_size})")
    return nil
  end

  entry_links = page1_entry_links + page2_entry_links
  unless link_to_page3
    if entry_links.length <= best_count
      logger.log("Best count #{best_count} not topped (#{entry_links.length})")
      return nil
    end

    logger.log("New best count: #{entry_links.length} with 2 pages of #{page_size}")
    return {
      best_result: {
        main_canonical_url: page[:canonical_url],
        main_fetch_url: page[:fetch_uri].to_s,
        links: entry_links,
        pattern: "paged_last",
        extra: "page_count: 2<br>page_size: #{page_size}<br>last_page:<a href=\"#{page2[:fetch_uri]}\">#{page2[:canonical_url]}</a>"
      },
      subpattern_priority: subpattern_priorities[:paged],
      count: entry_links.length
    }
  end

  known_entry_urls_set = entry_links
    .map { |link| link[:canonical_url] }
    .to_set
  link_to_next_page = link_to_page3
  link_to_last_page = nil
  next_page_number = 3

  while link_to_next_page
    link_to_last_page = link_to_next_page
    loop_page_result = extract_page_entry_links(
      link_to_next_page, next_page_number, good_masked_xpath, page_size, remaining_feed_item_urls,
      start_link_id, known_entry_urls_set, db, redirects, logger
    )

    if loop_page_result.nil?
      return nil
    end

    entry_links += loop_page_result[:page_entry_links]
    known_entry_urls_set.merge(loop_page_result[:page_entry_links].map { |link| link[:canonical_url] })
    link_to_next_page = loop_page_result[:link_to_next_page]
    next_page_number += 1
    remaining_feed_item_urls = remaining_feed_item_urls[loop_page_result[:page_entry_links].length...-1] || []
  end

  if entry_links.length <= best_count
    logger.log("Best count #{best_count} not topped (#{entry_links.length})")
    return nil
  end

  page_count = next_page_number - 1

  last_page_url_regex = make_page_url_regex(page_count)
  first_page_links_to_last_page = page_links.any? do |page_link|
    page_link[:host] == page[:fetch_uri].host && last_page_url_regex.match?(page_link[:canonical_url])
  end
  logger.log("New best count: #{entry_links.length} with #{page_count} pages of #{page_size}")
  {
    best_result: {
      main_canonical_url: page[:canonical_url],
      main_fetch_url: page[:fetch_uri].to_s,
      links: entry_links,
      pattern: first_page_links_to_last_page ? "paged_last" : "paged_next",
      extra: "page_count: #{page_count}<br>page_size: #{page_size}<br><a href=\"#{link_to_last_page[:url]}\">#{link_to_last_page[:canonical_url]}</a>"
    },
    subpattern_priority: subpattern_priorities[:paged],
    count: entry_links.length
  }
end

def extract_page_entry_links(
  link_to_page, page_number, masked_xpath, page_size, remaining_feed_item_urls, start_link_id,
  known_entry_urls_set, db, redirects, logger
)
  logger.log("Possible page #{page_number}: #{link_to_page[:canonical_url]}")
  page = fetch_page(start_link_id, link_to_page[:canonical_url], db)
  if page.nil?
    logger.log("Page #{page_number} not found in db: #{link_to_page[:canonical_url]}")
    return nil
  end
  page_doc = Nokogiri::HTML5(page[:content])

  page_classes_by_xpath = {}
  page_entry_link_elements = page_doc.xpath(masked_xpath)
  page_entry_links = page_entry_link_elements.filter_map.with_index do |element, index|
    # Redirects don't matter after we're out of feed
    link_redirects = index < remaining_feed_item_urls.length ? redirects : {}
    html_element_to_link(
      element, page[:fetch_uri], page_doc, page_classes_by_xpath, link_redirects, logger, true, false
    )
  end

  if page_entry_links.empty?
    logger.log("XPath doesn't work for page #{page_number}: #{masked_xpath}")
    return nil
  end

  page_known_urls = page_entry_links
    .map { |page_link| page_link[:canonical_url] }
    .filter { |page_url| known_entry_urls_set.include?(page_url) }
  unless page_known_urls.empty?
    logger.log("Page #{page_number} has known links: #{page_known_urls}")
    return nil
  end

  page_entry_urls = page_entry_links.map { |link| link[:canonical_url] }
  feed_overlap_length = [page_entry_urls.length, remaining_feed_item_urls.length].min
  unless page_entry_urls[0...feed_overlap_length] == remaining_feed_item_urls[0...feed_overlap_length]
    logger.log("Page #{page_number} doesn't overlap with feed")
    logger.log("Page urls: #{page_entry_urls[0...feed_overlap_length]}")
    logger.log("Feed urls: #{remaining_feed_item_urls[0...feed_overlap_length]}")
    return nil
  end

  page_links = extract_links(page, [page[:fetch_uri].host], redirects, logger, true, false)[:allowed_host_links]
  next_page_number = page_number + 1
  next_page_url_regex = make_page_url_regex(next_page_number)
  links_to_next_page = page_links.filter { |page_link| next_page_url_regex.match?(page_link[:canonical_url]) }

  if links_to_next_page.map { |page_link| page_link[:canonical_url] }.to_set.length > 1
    logger.log("Page #{page_number} #{page[:canonical_url]} has multiple page #{next_page_number} links: #{links_to_next_page}")
    return nil
  end

  link_to_next_page = links_to_next_page.first
  if link_to_next_page && page_entry_links.length != page_size
    logger.log("There are at least #{next_page_number} pages and page #{page_number} size (#{page_entry_links.length}) is not equal to expected page size (#{page_size})")
    return nil
  end

  { page_entry_links: page_entry_links, link_to_next_page: link_to_next_page }
end

def fetch_page(start_link_id, canonical_url, db)
  row = db.exec_params(
    "select fetch_url, content_type, content from pages where start_link_id = $1 and content is not null and canonical_url = $2",
    [start_link_id, canonical_url]
  ).first
  if row.nil?
    return nil
  end

  {
    canonical_url: canonical_url,
    fetch_uri: URI(row["fetch_url"]),
    content_type: row["content_type"],
    content: unescape_bytea(row["content"])
  }
end

def make_page_url_regex(next_page_number)
  Regexp.new("/page/?#{next_page_number}([^\\d]|$)")
end