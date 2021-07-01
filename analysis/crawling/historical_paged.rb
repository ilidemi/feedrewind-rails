require 'nokogumbo'
require 'set'
require_relative 'crawling'
require_relative 'db'
require_relative 'historical_common'
require_relative 'structs'

BLOGSPOT_POSTS_BY_DATE_REGEX = /(\(date-outer\)\[)\d+(.+\(post-outer\)\[)\d+/

def try_extract_paged(
  page1, page1_links, page_urls_set, feed_item_urls, feed_item_urls_set, best_count, subpattern_priorities,
  start_link_id, redirects, db, logger
)
  page_overlapping_links_count = nil
  feed_item_urls.each_with_index do |feed_item_url, index|
    if index == feed_item_urls.length - 1 && page_urls_set.include?(feed_item_url)
      page_overlapping_links_count = feed_item_urls.length
    elsif !page_urls_set.include?(feed_item_url)
      page_overlapping_links_count = index
    end
  end

  link_pattern_to_page2 = find_link_to_second_page(page1_links, page1, logger)
  return nil unless link_pattern_to_page2
  link_to_page2 = link_pattern_to_page2[:link]
  paging_pattern = link_pattern_to_page2[:paging_pattern]

  logger.log("Possible page 1: #{page1.canonical_url} (#{page_overlapping_links_count} overlaps)")

  links_by_masked_xpath = nil
  if paging_pattern == :blogspot
    page1_class_xpath_links = extract_links(page1, [page1.fetch_uri.host], redirects, logger, true, true)
    page1_links_grouped_by_date = page1_class_xpath_links.filter do |page_link|
      BLOGSPOT_POSTS_BY_DATE_REGEX.match(page_link.class_xpath)
    end
    page1_feed_links_grouped_by_date = page1_links_grouped_by_date.filter do |page_link|
      feed_item_urls_set.include?(page_link.canonical_url)
    end
    unless page1_feed_links_grouped_by_date.empty?
      links_by_masked_xpath = {}
      page1_feed_links_grouped_by_date.each do |page_feed_link|
        masked_xpath = page_feed_link
          .class_xpath
          .sub(BLOGSPOT_POSTS_BY_DATE_REGEX, '\1*\2*')
          .gsub(/\([^)]*\)/, '')
        links_by_masked_xpath[masked_xpath] = []
      end
      page1_links_grouped_by_date.each do |page_link|
        masked_xpath = page_link
          .class_xpath
          .sub(BLOGSPOT_POSTS_BY_DATE_REGEX, '\1*\2*')
          .gsub(/\([^)]*\)/, '')
        next unless links_by_masked_xpath.key?(masked_xpath)
        links_by_masked_xpath[masked_xpath] << page_link
      end
    end
  end

  if links_by_masked_xpath.nil?
    get_masked_xpaths_func = method(:get_single_masked_xpaths)
    links_by_masked_xpath = group_links_by_masked_xpath(
      page1_links, feed_item_urls_set, :xpath, get_masked_xpaths_func
    )
  end

  page_size_masked_xpaths = []
  page1_link_to_newest_post = page1_links
    .filter { |page_link| page_link.canonical_url == feed_item_urls.first }
    .first
  links_by_masked_xpath.each do |masked_xpath, masked_xpath_links|
    masked_xpath_link_urls = masked_xpath_links.map(&:canonical_url)
    feed_overlap_length = [masked_xpath_link_urls.length, feed_item_urls.length].min
    if masked_xpath_link_urls[0...feed_overlap_length] == feed_item_urls[0...feed_overlap_length]
      includes_newest_post = true
    else
      feed_minus_one_overlap_length = [masked_xpath_link_urls.length, feed_item_urls.length - 1].min
      if page1_link_to_newest_post &&
        masked_xpath_link_urls[0...feed_minus_one_overlap_length] == feed_item_urls[1..feed_minus_one_overlap_length]

        includes_newest_post = false
      else
        next
      end
    end

    masked_xpath_link_urls_set = masked_xpath_link_urls.to_set
    if masked_xpath_link_urls_set.length != masked_xpath_link_urls.length
      logger.log("Masked xpath #{masked_xpath} has duplicates: #{masked_xpath_link_urls}")
      next
    end

    xpath_page_size = includes_newest_post ? masked_xpath_link_urls.length : masked_xpath_link_urls.length + 1
    page_size_masked_xpaths << [xpath_page_size, masked_xpath, includes_newest_post]
  end

  if page_size_masked_xpaths.empty?
    logger.log("No good overlap with feed prefix")
    return nil
  end

  page_size_masked_xpaths_sorted = page_size_masked_xpaths
    .sort_by { |xpath_page_size, _, _| -xpath_page_size }
  logger.log("Max prefix: #{page_size_masked_xpaths.first[0]}")

  page2 = fetch_page(start_link_id, link_to_page2.canonical_url, db)
  if page2.nil?
    logger.log("Page 2 not found in db: #{link_to_page2.canonical_url}")
    return nil
  end
  logger.log("Possible page 2: #{link_to_page2.canonical_url}")
  page2_doc = Nokogiri::HTML5(page2.content)

  page2_classes_by_xpath = {}
  page1_entry_links = nil
  page2_entry_links = nil
  good_masked_xpath = nil
  page_size = nil
  remaining_feed_item_urls = nil

  page_size_masked_xpaths_sorted.each do |xpath_page_size, masked_xpath, includes_first_post|
    page2_xpath_link_elements = page2_doc.xpath(masked_xpath)
    page2_xpath_links = page2_xpath_link_elements.filter_map do |element|
      html_element_to_link(
        element, page2.fetch_uri, page2_doc, page2_classes_by_xpath, redirects, logger, true, false
      )
    end
    next if page2_xpath_links.empty?

    page1_xpath_links = links_by_masked_xpath[masked_xpath]
    page1_xpath_urls_set = page1_xpath_links
      .map(&:canonical_url)
      .to_set
    next if page2_xpath_links.any? do |page2_xpath_link|
      page1_xpath_urls_set.include?(page2_xpath_link.canonical_url)
    end
    next if page2_xpath_links.length > xpath_page_size

    page2_xpath_urls = page2_xpath_links.map(&:canonical_url)
    page2_feed_item_urls = feed_item_urls[xpath_page_size..-1] || []
    feed_overlap_length = [page2_xpath_urls.length, page2_feed_item_urls.length].min
    next unless page2_xpath_urls[0...feed_overlap_length] == page2_feed_item_urls[0...feed_overlap_length]

    if includes_first_post
      decorated_first_post_log = ''
      possible_page1_entry_links = page1_xpath_links
    else
      decorated_first_post_log = ", assuming the first post is decorated"
      possible_page1_entry_links = [page1_link_to_newest_post] + page1_xpath_links
    end
    next if page1_entry_links && page2_entry_links &&
      (possible_page1_entry_links + page2_xpath_links).length <= (page1_entry_links + page2_entry_links).length

    page1_entry_links = possible_page1_entry_links
    page2_entry_links = page2_xpath_links
    good_masked_xpath = masked_xpath
    page_size = xpath_page_size
    remaining_feed_item_urls = page2_feed_item_urls[page2_entry_links.length...-1] || []
    logger.log("XPath looks good for page 2: #{masked_xpath} (#{page1_entry_links.length} + #{page2_entry_links.length} links#{decorated_first_post_log})")
  end

  if page2_entry_links.nil? && paging_pattern != :blogspot
    page_size_masked_xpaths_sorted.each do |xpath_page_size, masked_xpath|
      masked_xpath_star_index = masked_xpath.index("*")
      masked_xpath_suffix_start = masked_xpath[0...masked_xpath_star_index].rindex("/")
      masked_xpath_suffix = masked_xpath[masked_xpath_suffix_start..-1]
      page2_xpath_suffix = "/" + masked_xpath_suffix.gsub("*", "1")
      page2_xpath_suffix_link_elements = page2_doc.xpath(page2_xpath_suffix)
      page2_xpath_suffix_links = page2_xpath_suffix_link_elements.filter_map do |element|
        html_element_to_link(
          element, page2.fetch_uri, page2_doc, page2_classes_by_xpath, redirects, logger, true, false
        )
      end
      next if page2_xpath_suffix_links.length != 1

      page2_xpath_suffix_link = page2_xpath_suffix_links.first
      page2_xpath_prefix_length = page2_xpath_suffix_link.xpath.length - masked_xpath_suffix.length
      page2_xpath_prefix = page2_xpath_suffix_link.xpath[0...page2_xpath_prefix_length]
      page2_masked_xpath = page2_xpath_prefix + masked_xpath_suffix

      page2_xpath_link_elements = page2_doc.xpath(page2_masked_xpath)
      page2_xpath_links = page2_xpath_link_elements.filter_map do |element|
        html_element_to_link(
          element, page2.fetch_uri, page2_doc, page2_classes_by_xpath, redirects, logger, true, false
        )
      end

      page1_xpath_links = links_by_masked_xpath[masked_xpath]
      page1_xpath_urls_set = page1_xpath_links
        .map(&:canonical_url)
        .to_set
      next if page2_xpath_links.any? do |page2_xpath_link|
        page1_xpath_urls_set.include?(page2_xpath_link.canonical_url)
      end
      next if page2_xpath_links.length > xpath_page_size

      page2_xpath_urls = page2_xpath_links.map(&:canonical_url)
      page2_feed_item_urls = feed_item_urls[xpath_page_size..-1] || []
      feed_overlap_length = [page2_xpath_urls.length, page2_feed_item_urls.length].min
      next unless page2_xpath_urls[0...feed_overlap_length] == page2_feed_item_urls[0...feed_overlap_length]

      page1_entry_links = page1_xpath_links
      page2_entry_links = page2_xpath_links
      good_masked_xpath = page2_masked_xpath
      page_size = xpath_page_size
      remaining_feed_item_urls = page2_feed_item_urls[page2_entry_links.length...-1] || []
      logger.log("Possible page 2: #{link_to_page2.canonical_url}")
      logger.log("XPath looks good for page 1: #{masked_xpath} (#{page1_entry_links.length} links)")
      logger.log("XPath looks good for page 2: #{page2_masked_xpath} (#{page2_entry_links.length} links)")
      break
    end
  end

  if page2_entry_links.nil?
    logger.log("Couldn't find an xpath matching page 1 and page 2")
    return nil
  end

  page2_links = extract_links(page2, [page2.fetch_uri.host], redirects, logger, true, false)
  link_to_page3 = find_link_to_next_page(page2_links, page2, 3, paging_pattern, logger)
  return nil if link_to_page3 == :multiple
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
        main_canonical_url: page1.canonical_url,
        main_fetch_url: page1.fetch_uri.to_s,
        links: entry_links,
        pattern: "paged_last",
        extra: "page_count: 2<br>page_size: #{page_size}<br>last_page:<a href=\"#{page2.fetch_uri}\">#{page2.canonical_url}</a>"
      },
      subpattern_priority: subpattern_priorities[:paged],
      count: entry_links.length
    }
  end

  known_entry_urls_set = entry_links
    .map(&:canonical_url)
    .to_set
  link_to_next_page = link_to_page3
  link_to_last_page = nil
  next_page_number = 3

  while link_to_next_page
    link_to_last_page = link_to_next_page
    loop_page_result = extract_page_entry_links(
      link_to_next_page, next_page_number, paging_pattern, good_masked_xpath, page_size,
      remaining_feed_item_urls, start_link_id, known_entry_urls_set, db, redirects, logger
    )

    if loop_page_result.nil?
      return nil
    end

    entry_links += loop_page_result[:page_entry_links]
    known_entry_urls_set.merge(loop_page_result[:page_entry_links].map(&:canonical_url))
    link_to_next_page = loop_page_result[:link_to_next_page]
    next_page_number += 1
    remaining_feed_item_urls = remaining_feed_item_urls[loop_page_result[:page_entry_links].length...-1] || []
  end

  if entry_links.length <= best_count
    logger.log("Best count #{best_count} not topped (#{entry_links.length})")
    return nil
  end

  page_count = next_page_number - 1

  if paging_pattern == :blogspot
    first_page_links_to_last_page = false
  else
    first_page_links_to_last_page = !!find_link_to_next_page(
      page1_links, page1, page_count, paging_pattern, logger
    )
  end
  logger.log("New best count: #{entry_links.length} with #{page_count} pages of #{page_size}")
  {
    best_result: {
      main_canonical_url: page1.canonical_url,
      main_fetch_url: page1.fetch_uri.to_s,
      links: entry_links,
      pattern: first_page_links_to_last_page ? "paged_last" : "paged_next",
      extra: "page_count: #{page_count}<br>page_size: #{page_size}<br><a href=\"#{link_to_last_page.url}\">#{link_to_last_page.canonical_url}</a>"
    },
    subpattern_priority: subpattern_priorities[:paged],
    count: entry_links.length
  }
end

def extract_page_entry_links(
  link_to_page, page_number, paging_pattern, masked_xpath, page_size, remaining_feed_item_urls, start_link_id,
  known_entry_urls_set, db, redirects, logger
)
  logger.log("Possible page #{page_number}: #{link_to_page.canonical_url}")
  page = fetch_page(start_link_id, link_to_page.canonical_url, db)
  if page.nil?
    logger.log("Page #{page_number} not found in db: #{link_to_page.canonical_url}")
    return nil
  end
  page_doc = nokogiri_html5(page.content)

  page_classes_by_xpath = {}
  page_entry_link_elements = page_doc.xpath(masked_xpath)
  page_entry_links = page_entry_link_elements.filter_map.with_index do |element, index|
    # Redirects don't matter after we're out of feed
    link_redirects = index < remaining_feed_item_urls.length ? redirects : {}
    html_element_to_link(
      element, page.fetch_uri, page_doc, page_classes_by_xpath, link_redirects, logger, true, false
    )
  end

  if page_entry_links.empty?
    logger.log("XPath doesn't work for page #{page_number}: #{masked_xpath}")
    return nil
  end

  page_known_urls = page_entry_links
    .map(&:canonical_url)
    .filter { |page_url| known_entry_urls_set.include?(page_url) }
  unless page_known_urls.empty?
    logger.log("Page #{page_number} has known links: #{page_known_urls}")
    return nil
  end

  page_entry_urls = page_entry_links.map(&:canonical_url)
  feed_overlap_length = [page_entry_urls.length, remaining_feed_item_urls.length].min
  unless page_entry_urls[0...feed_overlap_length] == remaining_feed_item_urls[0...feed_overlap_length]
    logger.log("Page #{page_number} doesn't overlap with feed")
    logger.log("Page urls: #{page_entry_urls[0...feed_overlap_length]}")
    logger.log("Feed urls: #{remaining_feed_item_urls[0...feed_overlap_length]}")
    return nil
  end

  page_links = extract_links(page, [page.fetch_uri.host], redirects, logger, true, false)
  next_page_number = page_number + 1
  link_to_next_page = find_link_to_next_page(page_links, page, next_page_number, paging_pattern, logger)
  return nil if link_to_next_page == :multiple
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
  return nil if row.nil?

  Page.new(canonical_url, URI(row["fetch_url"]), start_link_id, row["content_type"], unescape_bytea(row["content"]))
end

BLOGSPOT_QUERY_REGEX = /updated-max=([^&]+)/

def find_link_to_second_page(current_page_links, current_page, logger)
  blogspot_next_page_links = current_page_links.filter do |link|
    link.uri.path == "/search" &&
      link.uri.query &&
      BLOGSPOT_QUERY_REGEX.match(link.uri.query)
  end

  unless blogspot_next_page_links.empty?
    links_to_page2 = blogspot_next_page_links
    if links_to_page2.map { |link| link.canonical_url }.to_set.length > 1
      logger.log("Page #{current_page.canonical_url} has multiple page 2 links: #{links_to_page2}")
      return nil
    end

    return {
      link: links_to_page2.first,
      paging_pattern: :blogspot
    }
  end

  link_to_page2_path_regex = Regexp.new("/(:?index-?2[^/^\\d]*|(:?page)?2)/?$")
  link_to_page2_query_regex = /([^?^&]*page=)2(:?&|$)/
  links_to_page2 = current_page_links.filter do |link|
    link.uri.host == current_page.fetch_uri.host && (
      link_to_page2_path_regex.match?(link.uri.path) || link_to_page2_query_regex.match?(link.uri.query)
    )
  end
  return nil if links_to_page2.empty?

  if links_to_page2.map { |link| link.canonical_url }.to_set.length > 1
    logger.log("Page #{current_page.canonical_url} has multiple page 2 links: #{links_to_page2}")
    return nil
  end

  link = links_to_page2.first
  if link_to_page2_path_regex.match?(link.uri.path)
    page_number_index = link.uri.path.rindex('2')
    path_template = link.uri.path[0...page_number_index] + '%d' + link.uri.path[(page_number_index + 1)..-1]
    {
      link: link,
      paging_pattern: {
        host: link.uri.host,
        path_template: path_template
      },
    }
  else
    query_template = link_to_page2_query_regex.match(link.uri.query)[1] + '%d'
    {
      link: link,
      paging_pattern: {
        host: link.uri.host,
        path: link.uri.path,
        query_template: query_template
      },
    }
  end
end

def find_link_to_next_page(current_page_links, current_page, next_page_number, paging_pattern, logger)
  if paging_pattern == :blogspot
    return nil unless current_page.fetch_uri.path == "/search" &&
      current_page.fetch_uri.query &&
      (current_date_match = BLOGSPOT_QUERY_REGEX.match(current_page.fetch_uri.query))

    links_to_next_page = current_page_links.filter do |link|
      !link.xpath.start_with?("/html[1]/head[1]") &&
        link.uri.path == "/search" &&
        link.uri.query &&
        (next_date_match = BLOGSPOT_QUERY_REGEX.match(link.uri.query)) &&
        next_date_match[1] < current_date_match[1]
    end
  else
    if paging_pattern[:path_template]
      expected_path = paging_pattern[:path_template] % next_page_number
      links_to_next_page = current_page_links.filter do |link|
        link.uri.host == paging_pattern[:host] && link.uri.path == expected_path
      end
    else
      expected_query_substring = paging_pattern[:query_template] % next_page_number
      links_to_next_page = current_page_links.filter do |link|
        link.uri.host == paging_pattern[:host] && link.uri.query&.include?(expected_query_substring)
      end
    end
  end

  if links_to_next_page.map { |link| link.canonical_url }.to_set.length > 1
    logger.log("Page #{next_page_number - 1} #{current_page.canonical_url} has multiple page #{next_page_number} links: #{links_to_next_page}")
    return :multiple
  end

  links_to_next_page.first
end
