require 'set'
require_relative 'historical_common'
require_relative 'page_parsing'
require_relative 'structs'

PagedResult = Struct.new(:pattern, :links, :count, :extra, keyword_init: true)
Page1Result = Struct.new(:link_to_page2, :paged_state)
PartialPagedResult = Struct.new(:link_to_next_page, :next_page_number, :count, :paged_state)

Page2State = Struct.new(
  :paging_pattern, :paging_pattern_extra, :page1, :page1_links, :page1_extractions_by_masked_xpath,
  :page1_size_masked_xpaths_sorted
)
NextPageState = Struct.new(
  :paging_pattern, :paging_pattern_extra, :page_number, :entry_links, :known_entry_curis_set,
  :classless_masked_xpath, :page_sizes, :page1, :page1_links
)

PagedExtraction = Struct.new(:links, :xpath_name, :classless_masked_xpath)

BLOGSPOT_POSTS_BY_DATE_REGEX = /(\(date-outer\)\[)\d+(.+\(post-outer\)\[)\d+/

def try_extract_page1(
  page1, page1_links, page_curis_set, feed_entry_links, feed_entry_curis_set, feed_generator, curi_eq_cfg,
  logger
)
  link_pattern_to_page2 = find_link_to_page2(page1_links, page1, feed_generator, curi_eq_cfg, logger)
  return nil unless link_pattern_to_page2
  link_to_page2 = link_pattern_to_page2[:link]
  paging_pattern = link_pattern_to_page2[:paging_pattern]
  paging_pattern_extra = paging_pattern.is_a?(Hash) ? '' : "<br>paging_pattern: #{paging_pattern}"

  page_overlapping_links_count = feed_entry_links.included_prefix_length(page_curis_set)
  logger.log("Possible page 1: #{page1.curi} (#{page_overlapping_links_count} overlaps)")

  page1_extractions_by_masked_xpath = nil

  # Blogger has a known pattern with posts grouped by date
  if paging_pattern == :blogger
    page1_class_xpath_links = extract_links(page1, [page1.fetch_uri.host], nil, logger, true, true)
    page1_links_grouped_by_date = page1_class_xpath_links.filter do |page_link|
      BLOGSPOT_POSTS_BY_DATE_REGEX.match(page_link.class_xpath)
    end
    page1_feed_links_grouped_by_date = page1_links_grouped_by_date.filter do |page_link|
      feed_entry_curis_set.include?(page_link.curi)
    end
    unless page1_feed_links_grouped_by_date.empty?
      page1_extractions_by_masked_xpath = {}
      page1_feed_links_grouped_by_date.each do |page_feed_link|
        masked_class_xpath = page_feed_link
          .class_xpath
          .sub(BLOGSPOT_POSTS_BY_DATE_REGEX, '\1*\2*')
        masked_xpath = class_xpath_remove_classes(masked_class_xpath)
        page1_extractions_by_masked_xpath[masked_class_xpath] =
          PagedExtraction.new([], :class_xpath, masked_xpath)
      end
      page1_links_grouped_by_date.each do |page_link|
        masked_class_xpath = page_link
          .class_xpath
          .sub(BLOGSPOT_POSTS_BY_DATE_REGEX, '\1*\2*')
        next unless page1_extractions_by_masked_xpath.key?(masked_class_xpath)
        page1_extractions_by_masked_xpath[masked_class_xpath].links << page_link
      end
    end
  end

  # For all others, just extract all masked xpaths
  if page1_extractions_by_masked_xpath.nil?
    page1_links_by_masked_xpath_one_star =
      group_links_by_masked_xpath(page1_links, feed_entry_curis_set, :xpath, 1)
    page1_extractions_by_masked_xpath_one_star = page1_links_by_masked_xpath_one_star
      .to_h do |masked_xpath, masked_xpath_links|
      [masked_xpath, PagedExtraction.new(masked_xpath_links, :xpath, masked_xpath)]
    end

    page1_links_by_masked_xpath_two_stars =
      group_links_by_masked_xpath(page1_links, feed_entry_curis_set, :class_xpath, 2)
    page1_extractions_by_masked_xpath_two_stars = page1_links_by_masked_xpath_two_stars
      .to_h do |masked_class_xpath, masked_xpath_links|
      [
        masked_class_xpath,
        PagedExtraction.new(masked_xpath_links, :class_xpath, class_xpath_remove_classes(masked_class_xpath))
      ]
    end
    page1_extractions_by_masked_xpath = page1_extractions_by_masked_xpath_one_star
      .merge(page1_extractions_by_masked_xpath_two_stars)
  end

  # Filter masked xpaths to only ones that prefix feed
  page1_size_masked_xpaths = []
  page1_extractions_by_masked_xpath.each do |masked_xpath, page1_extraction|
    page1_xpath_links = page1_extraction.links
    page1_xpath_curis = page1_xpath_links.map(&:curi)
    is_overlap_matching = feed_entry_links.sequence_match?(page1_xpath_curis, curi_eq_cfg)
    if is_overlap_matching
      includes_newest_post = true
      extra_first_link = nil
    else
      is_overlap_minus_one_matching, extra_first_link =
        feed_entry_links.sequence_match_except_first?(page1_xpath_curis, curi_eq_cfg)
      if is_overlap_minus_one_matching && extra_first_link
        includes_newest_post = false
      else
        next
      end
    end

    masked_xpath_curis_set = page1_xpath_curis.to_canonical_uri_set(curi_eq_cfg)
    if masked_xpath_curis_set.length != page1_xpath_curis.length
      logger.log("Masked xpath #{masked_xpath} has duplicates: #{page1_xpath_curis.map(&:to_s)}")
      next
    end

    xpath_page_size = page1_xpath_curis.length + (includes_newest_post ? 0 : 1)
    page1_size_masked_xpaths <<
      [xpath_page_size, masked_xpath, includes_newest_post, extra_first_link]
  end

  if page1_size_masked_xpaths.empty?
    logger.log("No good overlap with feed prefix")
    return nil
  end

  page1_size_masked_xpaths_sorted = page1_size_masked_xpaths
    .sort_by
    .with_index do |page_size_masked_xpath, index|
    [
      -page_size_masked_xpath[0], # -page_size
      index # for stable sort, which should put header before footer
    ]
  end
  logger.log("Max prefix: #{page1_size_masked_xpaths.first[0]}")

  Page1Result.new(
    link_to_page2,
    Page2State.new(
      paging_pattern, paging_pattern_extra, page1, page1_links, page1_extractions_by_masked_xpath,
      page1_size_masked_xpaths_sorted
    )
  )
end

def try_extract_page2(page2, page2_state, feed_entry_links, curi_eq_cfg, logger)
  paging_pattern = page2_state.paging_pattern
  paging_pattern_extra = page2_state.paging_pattern_extra

  logger.log("Possible page 2: #{page2.curi}")
  page2_doc = Nokogiri::HTML5(page2.content)

  page2_classes_by_xpath = {}
  page1_entry_links = nil
  page2_entry_links = nil
  good_classless_masked_xpath = nil
  page_sizes = []

  # Look for matches on page 2 that overlap with feed
  page2_state.page1_size_masked_xpaths_sorted.each do
  |xpath_page1_size, page1_masked_xpath, page1_includes_first_post, extra_first_link|

    page1_extraction = page2_state.page1_extractions_by_masked_xpath[page1_masked_xpath]
    page1_xpath_links = page1_extraction.links
    page1_classless_masked_xpath = page1_extraction.classless_masked_xpath

    page2_classless_xpath_link_elements = page2_doc.xpath(page1_classless_masked_xpath)
    page2_classless_xpath_links = page2_classless_xpath_link_elements.filter_map do |element|
      html_element_to_link(
        element, page2.fetch_uri, page2_doc, page2_classes_by_xpath, nil, logger, true, true
      )
    end
    page2_xpath_links = page2_classless_xpath_links
      .filter { |link| class_xpath_match?(link.class_xpath, page1_masked_xpath) }
    next if page2_xpath_links.empty?

    page1_xpath_curis_set = page1_xpath_links
      .map(&:curi)
      .to_canonical_uri_set(curi_eq_cfg)
    next if page2_xpath_links
      .any? { |page2_xpath_link| page1_xpath_curis_set.include?(page2_xpath_link.curi) }

    page2_xpath_curis = page2_xpath_links.map(&:curi)
    is_overlap_matching = feed_entry_links.subsequence_match?(
      page2_xpath_curis, xpath_page1_size, curi_eq_cfg
    )
    next unless is_overlap_matching

    if page1_includes_first_post
      decorated_first_post_log = ''
      possible_page1_entry_links = page1_xpath_links
    else
      decorated_first_post_log = ", assuming the first post is decorated"
      possible_page1_entry_links = [extra_first_link] + page1_xpath_links
    end
    next if page1_entry_links && page2_entry_links &&
      (possible_page1_entry_links + page2_xpath_links).length <=
        (page1_entry_links + page2_entry_links).length

    page1_entry_links = possible_page1_entry_links
    page2_entry_links = page2_xpath_links
    good_classless_masked_xpath = page1_classless_masked_xpath
    page_sizes << xpath_page1_size << page2_xpath_links.length
    logger.log("XPath looks good for page 2: #{page1_masked_xpath} (#{page1_entry_links.length} + #{page2_entry_links.length} links#{decorated_first_post_log})")
  end

  # See if the first page had some sort of decoration, and links on the second page moved under another
  # parent but retained the inner structure
  if page2_entry_links.nil? && paging_pattern != :blogger
    page2_state.page1_size_masked_xpaths_sorted.each do |page1_size, page1_masked_xpath|
      page1_extraction = page2_state.page1_extractions_by_masked_xpath[page1_masked_xpath]
      page1_xpath_links = page1_extraction.links
      page1_xpath_name = page1_extraction.xpath_name

      masked_xpath_star_index = page1_masked_xpath.index("*")
      masked_xpath_suffix_start = page1_masked_xpath[...masked_xpath_star_index].rindex("/")
      masked_xpath_suffix = page1_masked_xpath[masked_xpath_suffix_start..]
      page2_classless_xpath_suffix_elements = page2_doc.xpath(
        "/" + class_xpath_remove_classes(masked_xpath_suffix)
      )
      page2_classless_xpath_suffix_links = page2_classless_xpath_suffix_elements
        .filter_map do |element|
        html_element_to_link(
          element, page2.fetch_uri, page2_doc, page2_classes_by_xpath, nil, logger, true,
          true
        )
      end
      page2_classless_xpath_suffix_first_links_by_xpath_prefix = page2_classless_xpath_suffix_links
        .each_with_object({}) do |link, first_links_by_xpath_prefix|

        xpath = link[page1_xpath_name]
        xpath_prefix = get_xpath_prefix(xpath, masked_xpath_suffix)
        next unless xpath_prefix

        first_links_by_xpath_prefix[xpath_prefix] = link unless first_links_by_xpath_prefix.key?(xpath_prefix)
      end
      page2_xpath_suffix_first_links = page2_classless_xpath_suffix_first_links_by_xpath_prefix
        .filter do |xpath_prefix, link|
        class_xpath_match?(link.class_xpath, xpath_prefix + masked_xpath_suffix)
      end
      next if page2_xpath_suffix_first_links.length != 1

      page2_xpath_prefix = page2_xpath_suffix_first_links.first.first
      page2_masked_xpath = page2_xpath_prefix + masked_xpath_suffix

      page2_xpath_classless_link_elements = page2_doc.xpath(
        class_xpath_remove_classes(page2_masked_xpath)
      )
      page2_xpath_classless_links = page2_xpath_classless_link_elements.filter_map do |element|
        html_element_to_link(
          element, page2.fetch_uri, page2_doc, page2_classes_by_xpath, nil, logger, true,
          true
        )
      end
      page2_xpath_links = page2_xpath_classless_links
        .filter { |link| class_xpath_match?(link.class_xpath, page2_masked_xpath) }

      page1_xpath_curis_set = page1_xpath_links
        .map(&:curi)
        .to_canonical_uri_set(curi_eq_cfg)
      next if page2_xpath_links.any? do |page2_xpath_link|
        page1_xpath_curis_set.include?(page2_xpath_link.curi)
      end

      page2_xpath_curis = page2_xpath_links.map(&:curi)
      is_overlap_matching = feed_entry_links.subsequence_match?(
        page2_xpath_curis, page1_size, curi_eq_cfg
      )
      next unless is_overlap_matching

      page1_entry_links = page1_xpath_links
      page2_entry_links = page2_xpath_links
      good_classless_masked_xpath = class_xpath_remove_classes(page2_masked_xpath)
      page_sizes << page1_size << page2_xpath_links.length
      logger.log("Possible page 2: #{page2.curi}")
      logger.log("XPath looks good for page 1: #{page1_masked_xpath} (#{page1_entry_links.length} links)")
      logger.log("XPath looks good for page 2: #{page2_masked_xpath} (#{page2_entry_links.length} links)")
      break
    end
  end

  if page2_entry_links.nil?
    logger.log("Couldn't find an xpath matching page 1 and page 2")
    return nil
  end

  page2_links = extract_links(page2, [page2.fetch_uri.host], nil, logger, true, false)
  link_to_page3 = find_link_to_next_page(
    page2_links, page2, curi_eq_cfg, 3, paging_pattern, logger
  )
  return nil if link_to_page3 == :multiple

  entry_links = page1_entry_links + page2_entry_links
  unless link_to_page3
    logger.log("Best count: #{entry_links.length} with 2 pages of #{page_sizes}")
    page_size_counts = page_sizes.each_with_object(Hash.new(0)) { |size, counts| counts[size] += 1 }
    return PagedResult.new(
      pattern: "paged_last",
      links: entry_links,
      count: entry_links.count,
      extra: "page_count: 2<br>page_sizes: #{page_size_counts}<br>xpath: #{good_classless_masked_xpath}<br>last_page:<a href=\"#{page2.fetch_uri}\">#{page2.curi}</a>#{paging_pattern_extra}"
    )
  end

  known_entry_curis_set = entry_links
    .map(&:curi)
    .to_canonical_uri_set(curi_eq_cfg)

  PartialPagedResult.new(
    link_to_page3,
    3,
    entry_links.count,
    NextPageState.new(
      paging_pattern, paging_pattern_extra, 3, entry_links, known_entry_curis_set,
      good_classless_masked_xpath, page_sizes, page2_state.page1, page2_state.page1_links
    )
  )
end

def try_extract_next_page(page, page_state, feed_entry_links, curi_eq_cfg, logger)
  paging_pattern = page_state.paging_pattern
  paging_pattern_extra = page_state.paging_pattern_extra
  page_number = page_state.page_number
  entry_links = page_state.entry_links
  known_entry_curis_set = page_state.known_entry_curis_set
  classless_masked_xpath = page_state.classless_masked_xpath

  logger.log("Possible page #{page_number}: #{page.curi}")

  page_classes_by_xpath = {}
  page_xpath_link_elements = page.document.xpath(classless_masked_xpath)
  page_xpath_links = page_xpath_link_elements.filter_map do |element|
    html_element_to_link(
      element, page.fetch_uri, page.document, page_classes_by_xpath, nil, logger, true, true
    )
  end

  if page_xpath_links.empty?
    logger.log("XPath doesn't work for page #{page_number}: #{classless_masked_xpath}")
    return nil
  end

  page_known_curis = page_xpath_links
    .map(&:curi)
    .filter { |page_uri| known_entry_curis_set.include?(page_uri) }
  unless page_known_curis.empty?
    logger.log("Page #{page_number} has known links: #{page_known_curis}")
    return nil
  end

  page_entry_curis = page_xpath_links.map(&:curi)
  is_overlap_matching = feed_entry_links.subsequence_match?(
    page_entry_curis, entry_links.length, curi_eq_cfg
  )
  unless is_overlap_matching
    logger.log("Page #{page_number} doesn't overlap with feed")
    logger.log("Page urls: #{page_entry_curis.map(&:to_s)}")
    logger.log("Feed urls (offset #{entry_links.length}): #{feed_entry_links}")
    return nil
  end

  page_links = extract_links(page, [page.fetch_uri.host], nil, logger, true, false)
  next_page_number = page_number + 1
  link_to_next_page = find_link_to_next_page(
    page_links, page, curi_eq_cfg, next_page_number, paging_pattern, logger
  )
  return nil if link_to_next_page == :multiple

  next_entry_links = entry_links + page_xpath_links
  next_known_entry_curis_set = (known_entry_curis_set.curis + page_xpath_links.map(&:curi))
    .to_canonical_uri_set(curi_eq_cfg)
  page_sizes = page_state.page_sizes + [page_xpath_links.length]

  if link_to_next_page
    PartialPagedResult.new(
      link_to_next_page,
      next_page_number,
      next_entry_links.count,
      NextPageState.new(
        paging_pattern, paging_pattern_extra, next_page_number, next_entry_links, next_known_entry_curis_set,
        classless_masked_xpath, page_sizes, page_state.page1, page_state.page1_links
      )
    )
  else
    page_count = page_number
    if paging_pattern == :blogger
      first_page_links_to_last_page = false
    else
      first_page_links_to_last_page = !!find_link_to_next_page(
        page_state.page1_links, page_state.page1, curi_eq_cfg, page_count, paging_pattern, logger
      )
    end

    logger.log("Best count: #{next_entry_links.length} with #{page_count} pages of #{page_sizes}")
    page_size_counts = page_sizes.each_with_object(Hash.new(0)) { |size, counts| counts[size] += 1 }

    PagedResult.new(
      pattern: first_page_links_to_last_page ? "paged_last" : "paged_next",
      links: next_entry_links,
      count: next_entry_links.count,
      extra: "page_count: #{page_count}<br>page_sizes: #{page_size_counts}<br>xpath: #{classless_masked_xpath}<br>last_page: <a href=\"#{page.fetch_uri}\">#{page.curi}</a>#{paging_pattern_extra}"
    )
  end
end

BLOGSPOT_QUERY_REGEX = /updated-max=([^&]+)/

def find_link_to_page2(current_page_links, current_page, feed_generator, curi_eq_cfg, logger)
  blogspot_next_page_links = current_page_links.filter do |link|
    link.uri.path == "/search" &&
      link.uri.query &&
      BLOGSPOT_QUERY_REGEX.match(link.uri.query)
  end

  if feed_generator == :blogger && !blogspot_next_page_links.empty?
    links_to_page2 = blogspot_next_page_links
    if links_to_page2
      .map(&:curi)
      .to_canonical_uri_set(curi_eq_cfg)
      .length > 1

      logger.log("Page #{current_page.curi} has multiple page 2 links: #{links_to_page2}")
      return nil
    end

    return {
      link: links_to_page2.first,
      paging_pattern: :blogger
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
    .map(&:curi)
    .to_canonical_uri_set(curi_eq_cfg)
    .length > 1

    logger.log("Page #{current_page.curi} has multiple page 2 links: #{links_to_page2}")
    return nil
  end

  link = links_to_page2.first
  if link_to_page2_path_regex.match?(link.uri.path)
    page_number_index = link.uri.path.rindex('2')
    path_template = link.uri.path[...page_number_index] + '%d' + link.uri.path[(page_number_index + 1)..]
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
  current_page_links, current_page, curi_eq_cfg, next_page_number, paging_pattern, logger
)
  if paging_pattern == :blogger
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
    .map(&:curi)
    .to_canonical_uri_set(curi_eq_cfg)
    .length > 1

    logger.log("Page #{next_page_number - 1} #{current_page.curi} has multiple page #{next_page_number} links: #{links_to_next_page}")
    return :multiple
  end

  links_to_next_page.first
end

def get_xpath_prefix(xpath, masked_xpath_suffix)
  xpath_prefix_length = xpath.length
  xpath_suffix = masked_xpath_suffix

  # Replace stars with the actual numbers right to left
  loop do
    suffix_prefix, star, suffix_suffix = xpath_suffix.rpartition("*")
    break if star.empty?
    return nil unless xpath.end_with?(suffix_suffix)

    xpath_prefix_length = xpath.length - suffix_suffix.length
    number_index = xpath[...xpath_prefix_length].rindex("[") + 1
    xpath_suffix = suffix_prefix + xpath[number_index...xpath_prefix_length] + suffix_suffix
    xpath_prefix_length = number_index
  end
  xpath_prefix_length = xpath[...xpath_prefix_length].rindex("/")

  xpath[...xpath_prefix_length]
end

def class_xpath_remove_classes(class_xpath)
  class_xpath.gsub(/\([^)]*\)/, '')
end

def class_xpath_match?(class_xpath, masked_xpath)
  return true unless masked_xpath.include?("(")

  xpath_remaining = class_xpath
  masked_xpath_remaining = masked_xpath

  loop do
    star_index = masked_xpath_remaining.index("*")
    if star_index
      return false unless xpath_remaining[...star_index] == masked_xpath_remaining[...star_index]

      xpath_remaining = xpath_remaining[star_index..]
      xpath_remaining = xpath_remaining[xpath_remaining.index("]")..]
      masked_xpath_remaining = masked_xpath_remaining[(star_index + 1)..]
    else
      return xpath_remaining == masked_xpath_remaining
    end
  end
end