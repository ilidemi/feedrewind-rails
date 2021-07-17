require 'set'
require_relative 'guided_crawling'
require_relative 'historical_common'
require_relative 'structs'

BLOGSPOT_POSTS_BY_DATE_REGEX = /(\(date-outer\)\[)\d+(.+\(post-outer\)\[)\d+/

def try_extract_paged(
  page1, page1_links, page_canonical_uris_set, feed_entry_canonical_uris, feed_entry_canonical_uris_set,
  canonical_equality_cfg, min_links_count, start_link_id, ctx, mock_http_client, db_storage, logger
)
  page_overlapping_links_count = nil
  feed_entry_canonical_uris.each_with_index do |feed_entry_canonical_uri, index|
    if index == feed_entry_canonical_uris.length - 1 && page_canonical_uris_set.include?(feed_entry_canonical_uri)
      page_overlapping_links_count = feed_entry_canonical_uris.length
    elsif !page_canonical_uris_set.include?(feed_entry_canonical_uri)
      page_overlapping_links_count = index
    end
  end

  link_pattern_to_page2 = find_link_to_second_page(page1_links, page1, canonical_equality_cfg, logger)
  return nil unless link_pattern_to_page2
  link_to_page2 = link_pattern_to_page2[:link]
  paging_pattern = link_pattern_to_page2[:paging_pattern]

  logger.log("Possible page 1: #{page1.canonical_uri} (#{page_overlapping_links_count} overlaps)")

  links_by_masked_xpath = nil
  if paging_pattern == :blogspot
    page1_class_xpath_links = extract_links(page1, [page1.fetch_uri.host], ctx.redirects, logger, true, true)
    page1_links_grouped_by_date = page1_class_xpath_links.filter do |page_link|
      BLOGSPOT_POSTS_BY_DATE_REGEX.match(page_link.class_xpath)
    end
    page1_feed_links_grouped_by_date = page1_links_grouped_by_date.filter do |page_link|
      feed_entry_canonical_uris_set.include?(page_link.canonical_uri)
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
      page1_links, feed_entry_canonical_uris_set, :xpath, get_masked_xpaths_func
    )
  end

  page_size_masked_xpaths = []
  page1_link_to_newest_post = page1_links
    .filter { |page_link| canonical_uri_equal?(page_link.canonical_uri, feed_entry_canonical_uris.first, canonical_equality_cfg) }
    .first
  links_by_masked_xpath.each do |masked_xpath, masked_xpath_links|
    masked_xpath_canonical_uris = masked_xpath_links.map(&:canonical_uri)
    feed_overlap_length = [masked_xpath_canonical_uris.length, feed_entry_canonical_uris.length].min
    is_overlap_matching = masked_xpath_canonical_uris[0...feed_overlap_length]
      .zip(feed_entry_canonical_uris[0...feed_overlap_length])
      .all? { |xpath_uri, entry_uri| canonical_uri_equal?(xpath_uri, entry_uri, canonical_equality_cfg) }
    if is_overlap_matching
      includes_newest_post = true
    else
      feed_minus_one_overlap_length = [masked_xpath_canonical_uris.length, feed_entry_canonical_uris.length - 1].min
      is_overlap_minus_one_matching = masked_xpath_canonical_uris[0...feed_minus_one_overlap_length]
        .zip(feed_entry_canonical_uris[1..feed_minus_one_overlap_length])
        .all? { |xpath_uri, entry_uri| canonical_uri_equal?(xpath_uri, entry_uri, canonical_equality_cfg) }
      if page1_link_to_newest_post && is_overlap_minus_one_matching
        includes_newest_post = false
      else
        next
      end
    end

    masked_xpath_canonical_uris_set = masked_xpath_canonical_uris.to_canonical_uri_set(canonical_equality_cfg)
    if masked_xpath_canonical_uris_set.length != masked_xpath_canonical_uris.length
      logger.log("Masked xpath #{masked_xpath} has duplicates: #{masked_xpath_canonical_uris}")
      next
    end

    xpath_page_size = masked_xpath_canonical_uris.length + (includes_newest_post ? 0 : 1)
    page_size_masked_xpaths << [xpath_page_size, masked_xpath, includes_newest_post]
  end

  if page_size_masked_xpaths.empty?
    logger.log("No good overlap with feed prefix")
    return nil
  end

  page_size_masked_xpaths_sorted = page_size_masked_xpaths
    .sort_by
    .with_index do |page_size_masked_xpath, index|
    [
      -page_size_masked_xpath[0], # -page_size
      index # for stable sort, which should put header before footer
    ]
  end
  logger.log("Max prefix: #{page_size_masked_xpaths.first[0]}")

  page2 = crawl_request(link_to_page2, ctx, mock_http_client, nil, false, start_link_id, db_storage, logger)
  unless page2 && page2.is_a?(Page) && page2.content
    logger.log("Page 2 is not a page: #{page2}")
    return nil
  end
  logger.log("Possible page 2: #{link_to_page2.canonical_uri}")
  page2_doc = Nokogiri::HTML5(page2.content)

  page2_classes_by_xpath = {}
  page1_entry_links = nil
  page2_entry_links = nil
  good_masked_xpath = nil
  page_size = nil
  remaining_feed_entry_canonical_uris = nil

  page_size_masked_xpaths_sorted.each do |xpath_page_size, masked_xpath, includes_first_post|
    page2_xpath_link_elements = page2_doc.xpath(masked_xpath)
    page2_xpath_links = page2_xpath_link_elements.filter_map do |element|
      html_element_to_link(
        element, page2.fetch_uri, page2_doc, page2_classes_by_xpath, ctx.redirects, logger, true, false
      )
    end
    next if page2_xpath_links.empty?

    page1_xpath_links = links_by_masked_xpath[masked_xpath]
    page1_xpath_canonical_uris_set = page1_xpath_links
      .map(&:canonical_uri)
      .to_canonical_uri_set(canonical_equality_cfg)
    next if page2_xpath_links.any? do |page2_xpath_link|
      page1_xpath_canonical_uris_set.include?(page2_xpath_link.canonical_uri)
    end
    next if page2_xpath_links.length > xpath_page_size

    page2_xpath_canonical_uris = page2_xpath_links.map(&:canonical_uri)
    page2_feed_entry_canonical_uris = feed_entry_canonical_uris[xpath_page_size..-1] || []
    feed_overlap_length = [page2_xpath_canonical_uris.length, page2_feed_entry_canonical_uris.length].min
    is_overlap_matching = page2_xpath_canonical_uris[0...feed_overlap_length]
      .zip(page2_feed_entry_canonical_uris[0...feed_overlap_length])
      .all? { |xpath_uri, feed_uri| canonical_uri_equal?(xpath_uri, feed_uri, canonical_equality_cfg) }
    next unless is_overlap_matching

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
    remaining_feed_entry_canonical_uris = page2_feed_entry_canonical_uris[page2_entry_links.length...-1] || []
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
          element, page2.fetch_uri, page2_doc, page2_classes_by_xpath, ctx.redirects, logger, true, false
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
          element, page2.fetch_uri, page2_doc, page2_classes_by_xpath, ctx.redirects, logger, true, false
        )
      end

      page1_xpath_links = links_by_masked_xpath[masked_xpath]
      page1_xpath_canonical_uris_set = page1_xpath_links
        .map(&:canonical_uri)
        .to_canonical_uri_set(canonical_equality_cfg)
      next if page2_xpath_links.any? do |page2_xpath_link|
        page1_xpath_canonical_uris_set.include?(page2_xpath_link.canonical_uri)
      end
      next if page2_xpath_links.length > xpath_page_size

      page2_xpath_canonical_uris = page2_xpath_links.map(&:canonical_uri)
      page2_feed_entry_canonical_uris = feed_entry_canonical_uris[xpath_page_size..-1] || []
      feed_overlap_length = [page2_xpath_canonical_uris.length, page2_feed_entry_canonical_uris.length].min
      is_overlap_matching = page2_xpath_canonical_uris[0...feed_overlap_length]
        .zip(page2_feed_entry_canonical_uris[0...feed_overlap_length])
        .all? { |xpath_uri, entry_uri| canonical_uri_equal?(xpath_uri, entry_uri, canonical_equality_cfg) }
      next unless is_overlap_matching

      page1_entry_links = page1_xpath_links
      page2_entry_links = page2_xpath_links
      good_masked_xpath = page2_masked_xpath
      page_size = xpath_page_size
      remaining_feed_entry_canonical_uris = page2_feed_entry_canonical_uris[page2_entry_links.length...-1] || []
      logger.log("Possible page 2: #{link_to_page2.canonical_uri}")
      logger.log("XPath looks good for page 1: #{masked_xpath} (#{page1_entry_links.length} links)")
      logger.log("XPath looks good for page 2: #{page2_masked_xpath} (#{page2_entry_links.length} links)")
      break
    end
  end

  if page2_entry_links.nil?
    logger.log("Couldn't find an xpath matching page 1 and page 2")
    return nil
  end

  page2_links = extract_links(page2, [page2.fetch_uri.host], ctx.redirects, logger, true, false)
  link_to_page3 = find_link_to_next_page(
    page2_links, page2, canonical_equality_cfg, 3, paging_pattern, logger
  )
  return nil if link_to_page3 == :multiple
  if link_to_page3 && page2_entry_links.length != page_size
    raise "There are at least 3 pages and page 2 size (#{page2_entry_links.length}) is not equal to expected page size (#{page_size})"
  end

  entry_links = page1_entry_links + page2_entry_links
  unless link_to_page3
    if entry_links.length < min_links_count
      logger.log("Min links count #{min_links_count} not reached (#{entry_links.length})")
      return nil
    end

    logger.log("New best count: #{entry_links.length} with 2 pages of #{page_size}")
    return {
      main_canonical_url: page1.canonical_uri.to_s,
      main_fetch_url: page1.fetch_uri.to_s,
      links: entry_links,
      pattern: "paged_last",
      extra: "page_count: 2<br>page_size: #{page_size}<br>last_page:<a href=\"#{page2.fetch_uri}\">#{page2.canonical_uri}</a>",
      count: entry_links.length
    }
  end

  known_entry_canonical_uris_set = entry_links
    .map(&:canonical_uri)
    .to_canonical_uri_set(canonical_equality_cfg)
  link_to_next_page = link_to_page3
  link_to_last_page = nil
  next_page_number = 3

  while link_to_next_page
    link_to_last_page = link_to_next_page
    loop_page_result = extract_page_entry_links(
      link_to_next_page, next_page_number, paging_pattern, good_masked_xpath, page_size,
      remaining_feed_entry_canonical_uris, start_link_id, known_entry_canonical_uris_set,
      canonical_equality_cfg, ctx, mock_http_client, db_storage, logger
    )

    if loop_page_result.nil?
      return nil
    end

    entry_links += loop_page_result[:page_entry_links]
    known_entry_canonical_uris_set.merge!(
      loop_page_result[:page_entry_links].map(&:canonical_uri)
    )
    link_to_next_page = loop_page_result[:link_to_next_page]
    next_page_number += 1
    remaining_feed_entry_canonical_uris = remaining_feed_entry_canonical_uris[loop_page_result[:page_entry_links].length...-1] || []
  end

  if entry_links.length < min_links_count
    logger.log("Min links count #{min_links_count} not reached (#{entry_links.length})")
    return nil
  end

  page_count = next_page_number - 1

  if paging_pattern == :blogspot
    first_page_links_to_last_page = false
  else
    first_page_links_to_last_page = !!find_link_to_next_page(
      page1_links, page1, canonical_equality_cfg, page_count, paging_pattern, logger
    )
  end
  logger.log("New best count: #{entry_links.length} with #{page_count} pages of #{page_size}")
  {
    main_canonical_url: page1.canonical_uri.to_s,
    main_fetch_url: page1.fetch_uri.to_s,
    links: entry_links,
    pattern: first_page_links_to_last_page ? "paged_last" : "paged_next",
    extra: "page_count: #{page_count}<br>page_size: #{page_size}<br><a href=\"#{link_to_last_page.url}\">#{link_to_last_page.canonical_uri}</a>",
    count: entry_links.length
  }
end

def extract_page_entry_links(
  link_to_page, page_number, paging_pattern, masked_xpath, page_size, remaining_feed_entry_canonical_uris,
  start_link_id, known_entry_canonical_uris_set, canonical_equality_cfg, ctx, mock_http_client, db_storage,
  logger
)
  logger.log("Possible page #{page_number}: #{link_to_page.canonical_uri}")
  page = crawl_request(link_to_page, ctx, mock_http_client, nil, false, start_link_id, db_storage, logger)
  unless page && page.is_a?(Page) && page.document
    logger.log("Page #{page_number} is not a page: #{page}")
    return nil
  end

  page_classes_by_xpath = {}
  page_entry_link_elements = page.document.xpath(masked_xpath)
  page_entry_links = page_entry_link_elements.filter_map.with_index do |element, index|
    # Redirects don't matter after we're out of feed
    link_redirects = index < remaining_feed_entry_canonical_uris.length ? ctx.redirects : {}
    html_element_to_link(
      element, page.fetch_uri, page.document, page_classes_by_xpath, link_redirects, logger, true, false
    )
  end

  if page_entry_links.empty?
    logger.log("XPath doesn't work for page #{page_number}: #{masked_xpath}")
    return nil
  end

  page_known_canonical_uris = page_entry_links
    .map(&:canonical_uri)
    .filter { |page_uri| known_entry_canonical_uris_set.include?(page_uri) }
  unless page_known_canonical_uris.empty?
    logger.log("Page #{page_number} has known links: #{page_known_canonical_uris}")
    return nil
  end

  page_entry_canonical_uris = page_entry_links.map(&:canonical_uri)
  feed_overlap_length = [page_entry_canonical_uris.length, remaining_feed_entry_canonical_uris.length].min
  is_overlap_matching = page_entry_canonical_uris[0...feed_overlap_length]
    .zip(remaining_feed_entry_canonical_uris[0...feed_overlap_length])
    .all? { |xpath_uri, entry_uri| canonical_uri_equal?(xpath_uri, entry_uri, canonical_equality_cfg) }
  unless is_overlap_matching
    logger.log("Page #{page_number} doesn't overlap with feed")
    logger.log("Page urls: #{page_entry_canonical_uris[0...feed_overlap_length]}")
    logger.log("Feed urls: #{remaining_feed_entry_canonical_uris[0...feed_overlap_length]}")
    return nil
  end

  page_links = extract_links(page, [page.fetch_uri.host], ctx.redirects, logger, true, false)
  next_page_number = page_number + 1
  link_to_next_page = find_link_to_next_page(
    page_links, page, canonical_equality_cfg, next_page_number, paging_pattern, logger
  )
  return nil if link_to_next_page == :multiple
  if link_to_next_page && page_entry_links.length != page_size
    raise "There are at least #{next_page_number} pages and page #{page_number} size (#{page_entry_links.length}) is not equal to expected page size (#{page_size})"
  end

  { page_entry_links: page_entry_links, link_to_next_page: link_to_next_page }
end

BLOGSPOT_QUERY_REGEX = /updated-max=([^&]+)/

def find_link_to_second_page(current_page_links, current_page, canonical_equality_cfg, logger)
  blogspot_next_page_links = current_page_links.filter do |link|
    link.uri.path == "/search" &&
      link.uri.query &&
      BLOGSPOT_QUERY_REGEX.match(link.uri.query)
  end

  unless blogspot_next_page_links.empty?
    links_to_page2 = blogspot_next_page_links
    if links_to_page2
      .map(&:canonical_uri)
      .to_canonical_uri_set(canonical_equality_cfg)
      .length > 1

      logger.log("Page #{current_page.canonical_uri} has multiple page 2 links: #{links_to_page2}")
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

  if links_to_page2
    .map(&:canonical_uri)
    .to_canonical_uri_set(canonical_equality_cfg)
    .length > 1

    logger.log("Page #{current_page.canonical_uri} has multiple page 2 links: #{links_to_page2}")
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

def find_link_to_next_page(
  current_page_links, current_page, canonical_equality_cfg, next_page_number, paging_pattern, logger
)
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

  if links_to_next_page
    .map(&:canonical_uri)
    .to_canonical_uri_set(canonical_equality_cfg)
    .length > 1

    logger.log("Page #{next_page_number - 1} #{current_page.canonical_uri} has multiple page #{next_page_number} links: #{links_to_next_page}")
    return :multiple
  end

  links_to_next_page.first
end

