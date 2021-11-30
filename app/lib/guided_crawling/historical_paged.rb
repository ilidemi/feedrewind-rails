require 'set'
require_relative 'historical_common'
require_relative 'page_parsing'
require_relative 'structs'
require_relative 'title'

Page1Result = Struct.new(
  :main_link, :link_to_page2, :speculative_count, :count, :paged_state, keyword_init: true
)
PagedResult = Struct.new(
  :main_link, :pattern, :links, :speculative_count, :count, :extra, keyword_init: true
)
PartialPagedResult = Struct.new(
  :main_link, :link_to_next_page, :next_page_number, :links, :speculative_count, :count, :paged_state,
  keyword_init: true
)

Page2State = Struct.new(
  :is_certain, :paging_pattern, :page1, :page1_links, :page1_extractions, :main_link, keyword_init: true
)
Page1Extraction = Struct.new(
  :masked_xpath, :links, :xpath_name, :classless_masked_xpath, :log_lines, :title_relative_xpaths, :page_size,
  :includes_newest_post, :extra_first_link, keyword_init: true
)

NextPageState = Struct.new(
  :paging_pattern, :page_number, :known_entry_curis_set, :classless_masked_xpath, :title_relative_xpaths,
  :xpath_extra, :page_sizes, :page1, :page1_links, :main_link, keyword_init: true
)

BloggerMaskedXpathExtraction = Struct.new(
  :unfiltered_links, :xpath_name, :log_lines, :title_relative_xpaths, keyword_init: true
)

BLOGSPOT_POSTS_BY_DATE_REGEX = /(\(date-outer\)\[)\d+(.+\(post-outer\)\[)\d+/

def try_extract_page1(
  page1_link, page1, page1_links, page_curis_set, feed_entry_links, feed_entry_curis_titles_map,
  feed_generator, extractions_by_masked_xpath_by_star_count, curi_eq_cfg, logger
)
  link_pattern_to_page2 = find_link_to_page2(page1_links, page1, feed_generator, curi_eq_cfg, logger)
  return nil unless link_pattern_to_page2

  link_to_page2 = link_pattern_to_page2[:link]
  is_page2_certain = link_pattern_to_page2[:is_certain]
  paging_pattern = link_pattern_to_page2[:paging_pattern]

  page_overlapping_links_count = feed_entry_links.included_prefix_length(page_curis_set)
  logger.info("Possible page 1: #{page1.curi} (paging pattern: #{paging_pattern}, #{page_overlapping_links_count} overlaps)")

  extractions_by_masked_xpath = nil

  # Blogger has a known pattern with posts grouped by date
  if paging_pattern == :blogger
    page1_class_xpath_links = extract_links(
      page1.document, page1.fetch_uri, [page1.fetch_uri.host], nil, logger, true, true
    )
    page1_links_grouped_by_date = page1_class_xpath_links
      .filter { |page_link| BLOGSPOT_POSTS_BY_DATE_REGEX.match(page_link.class_xpath) }
    page1_feed_links_grouped_by_date = page1_links_grouped_by_date
      .filter { |page_link| feed_entry_curis_titles_map.include?(page_link.curi) }

    unless page1_feed_links_grouped_by_date.empty?
      extractions_by_masked_xpath = {}
      title_relative_xpath = TitleRelativeXpath.new("", :blogger)
      page1_feed_links_grouped_by_date.each do |page_feed_link|
        masked_class_xpath = page_feed_link
          .class_xpath
          .sub(BLOGSPOT_POSTS_BY_DATE_REGEX, '\1*\2*')
        extractions_by_masked_xpath[masked_class_xpath] = BloggerMaskedXpathExtraction.new(
          unfiltered_links: [],
          xpath_name: :class_xpath,
          log_lines: [],
          title_relative_xpaths: [title_relative_xpath]
        )
      end
      page1_links_grouped_by_date.each do |page_link|
        masked_class_xpath = page_link
          .class_xpath
          .sub(BLOGSPOT_POSTS_BY_DATE_REGEX, '\1*\2*')
        next unless extractions_by_masked_xpath.key?(masked_class_xpath)

        page_link_title_value = get_element_title(page_link.element)
        page_link.title = create_link_title(page_link_title_value, title_relative_xpath)
        extractions_by_masked_xpath[masked_class_xpath].unfiltered_links << page_link
      end
    end
  end

  # For all others, just extract all masked xpaths
  unless extractions_by_masked_xpath
    extractions_by_masked_xpath = extractions_by_masked_xpath_by_star_count[1]
      .merge(extractions_by_masked_xpath_by_star_count[2])
  end

  # Filter masked xpaths to only ones that prefix feed
  page1_extractions = []
  extractions_by_masked_xpath.each do |masked_xpath, extraction|
    links = extraction.unfiltered_links
    curis = links.map(&:curi)
    next if curis.any? { |curi| canonical_uri_equal?(curi, link_to_page2.curi, curi_eq_cfg) }

    is_overlap_matching = feed_entry_links.sequence_match(curis, curi_eq_cfg)
    if is_overlap_matching
      includes_newest_post = true
      extra_first_link = nil
    else
      is_overlap_minus_one_matching, extra_first_link =
        feed_entry_links.sequence_match_except_first?(curis, curi_eq_cfg)
      if is_overlap_minus_one_matching && extra_first_link
        includes_newest_post = false
      else
        next
      end
    end

    masked_xpath_curis_set = curis.to_canonical_uri_set(curi_eq_cfg)
    if masked_xpath_curis_set.length != curis.length
      logger.info("Masked xpath #{masked_xpath} has duplicates: #{curis.map(&:to_s)}")
      next
    end

    page_size = curis.length + (includes_newest_post ? 0 : 1)
    page1_extractions << Page1Extraction.new(
      masked_xpath: masked_xpath,
      links: links,
      xpath_name: extraction.xpath_name,
      classless_masked_xpath: class_xpath_remove_classes(masked_xpath),
      log_lines: extraction.log_lines,
      title_relative_xpaths: extraction.title_relative_xpaths,
      page_size: page_size,
      includes_newest_post: includes_newest_post,
      extra_first_link: extra_first_link
    )
  end

  if page1_extractions.empty?
    logger.info("No good overlap with feed prefix")
    return nil
  end

  page1_extractions_sorted = page1_extractions
    .sort_by
    .with_index do |page1_extraction, index|
    [
      -page1_extraction.page_size, # page size descending
      index # for stable sort
    ]
  end
  #noinspection RubyNilAnalysis
  max_page1_size = page1_extractions_sorted.first.page_size
  logger.info("Max prefix: #{max_page1_size}")

  Page1Result.new(
    main_link: page1_link,
    link_to_page2: link_to_page2,
    speculative_count: 2 * max_page1_size + 1,
    count: nil,
    paged_state: Page2State.new(
      is_certain: is_page2_certain,
      paging_pattern: paging_pattern,
      page1: page1,
      page1_links: page1_links,
      page1_extractions: page1_extractions,
      main_link: page1_link
    )
  )
end

def try_extract_page2(page2, page2_state, feed_entry_links, curi_eq_cfg, logger)
  is_page2_certain = page2_state.is_certain
  paging_pattern = page2_state.paging_pattern
  page1_link = page2_state.main_link

  logger.info("Possible page 2: #{page2.curi}")
  page2_doc = Nokogiri::HTML5(page2.content)

  page2_classes_by_xpath = {}
  page1_entry_links = nil
  page2_entry_links = nil
  best_classless_masked_xpath = nil
  best_title_relative_xpaths = nil
  best_xpath_extra = nil
  page_sizes = nil

  page2_links = extract_links(
    page2.document, page2.fetch_uri, [page2.fetch_uri.host], nil, logger, true, false
  )
  link_to_page3 = find_link_to_next_page(page2_links, page2, curi_eq_cfg, 3, paging_pattern, logger)
  if link_to_page3 == :multiple
    logger.info("Multiple links to page 3")
    return nil
  end

  neighbor_page_links = [page1_link] + (link_to_page3 ? [link_to_page3] : [])

  # Look for matches on page 2 that overlap with feed
  page2_state.page1_extractions.each do |page1_extraction|
    page1_xpath_links = page1_extraction.links
    page1_masked_xpath = page1_extraction.masked_xpath
    page1_size = page1_extraction.page_size
    page1_classless_masked_xpath = page1_extraction.classless_masked_xpath

    page2_classless_xpath_link_elements = page2_doc.xpath(page1_classless_masked_xpath)
    page2_classless_xpath_links = page2_classless_xpath_link_elements.filter_map do |element|
      populate_link_title(
        html_element_to_link(
          element, page2.fetch_uri, page2_doc, page2_classes_by_xpath, nil, logger, true, true
        ),
        page1_extraction.title_relative_xpaths
      )
    end
    page2_xpath_links = page2_classless_xpath_links
      .filter { |link| class_xpath_match?(link.class_xpath, page1_masked_xpath) }
    next if page2_xpath_links.empty?

    next if page2_xpath_links.any? do |link|
      neighbor_page_links.any? do |neighbor_link|
        canonical_uri_equal?(link.curi, neighbor_link.curi, curi_eq_cfg)
      end
    end

    page1_xpath_curis_set = page1_xpath_links
      .map(&:curi)
      .to_canonical_uri_set(curi_eq_cfg)
    next if page2_xpath_links
      .any? { |page2_xpath_link| page1_xpath_curis_set.include?(page2_xpath_link.curi) }

    page2_xpath_curis = page2_xpath_links.map(&:curi)
    is_overlap_matching = feed_entry_links.subsequence_match(page2_xpath_curis, page1_size, curi_eq_cfg)
    next unless is_overlap_matching

    log_lines = page1_extraction.log_lines.clone
    if page1_extraction.includes_newest_post
      possible_page1_entry_links = page1_xpath_links
    else
      log_lines << "the newest post is decorated"
      possible_page1_entry_links = [page1_extraction.extra_first_link] + page1_xpath_links
    end
    next if page1_entry_links && page2_entry_links &&
      (possible_page1_entry_links + page2_xpath_links).length <=
        (page1_entry_links + page2_entry_links).length

    page1_entry_links = possible_page1_entry_links
    page2_entry_links = page2_xpath_links
    best_classless_masked_xpath = page1_classless_masked_xpath
    best_title_relative_xpaths = page1_extraction.title_relative_xpaths
    log_lines << "#{page2_entry_links.length} page 2 links"
    log_str = join_log_lines(log_lines)
    best_xpath_extra = "xpath: #{page1_masked_xpath}#{log_str}"
    page_sizes = [page1_size, page2_xpath_links.length]
    logger.info("XPath from page 1 looks good for page 2: #{page1_masked_xpath}#{log_str}")
  end

  # See if the first page had some sort of decoration, and links on the second page moved under another
  # parent but retained the inner structure
  if page2_entry_links.nil? && is_page2_certain && paging_pattern != :blogger
    page2_state.page1_extractions.each do |page1_extraction|
      page1_xpath_links = page1_extraction.links
      page1_masked_xpath = page1_extraction.masked_xpath
      page1_size = page1_extraction.page_size
      page1_xpath_name = page1_extraction.xpath_name

      page2_log_lines = ["first page is decorated"]

      # For example, start with /div(x)[1]/article(y)[*]/a(z)[1]
      masked_xpath_star_index = page1_masked_xpath.index("*")
      masked_xpath_suffix_start = page1_masked_xpath[...masked_xpath_star_index].rindex("/")
      masked_xpath_suffix = page1_masked_xpath[masked_xpath_suffix_start..] # /article(y)[*]/a(z)[1]
      page2_classless_xpath_suffix_elements = page2_doc.xpath(
        "/" + class_xpath_remove_classes(masked_xpath_suffix) # //article[*]/a[1]
      )
      page2_classless_xpath_suffix_links = page2_classless_xpath_suffix_elements.filter_map do |element|
        populate_link_title(
          html_element_to_link(
            element, page2.fetch_uri, page2_doc, page2_classes_by_xpath, nil, logger, true, true
          ),
          page1_extraction.title_relative_xpaths
        )
      end
      page2_classless_xpath_suffix_first_links_by_xpath_prefix = page2_classless_xpath_suffix_links
        .each_with_object({}) do |link, first_links_by_xpath_prefix|

        xpath = link[page1_xpath_name] # For example, /div(x)[2]/article(y)[*]/a(z)[1]
        xpath_prefix = get_xpath_prefix(xpath, masked_xpath_suffix) # /div(x)[2]
        next unless xpath_prefix

        first_links_by_xpath_prefix[xpath_prefix] = link unless first_links_by_xpath_prefix.key?(xpath_prefix)
      end
      page2_xpath_suffix_first_links = page2_classless_xpath_suffix_first_links_by_xpath_prefix
        .filter do |xpath_prefix, link|
        class_xpath_match?(link.class_xpath, xpath_prefix + masked_xpath_suffix)
      end
      next if page2_xpath_suffix_first_links.length != 1

      # Found the masked xpath for page 2, now extract links for it
      page2_xpath_prefix = page2_xpath_suffix_first_links.first.first
      page2_masked_xpath = page2_xpath_prefix + masked_xpath_suffix
      page2_classless_masked_xpath = class_xpath_remove_classes(page2_masked_xpath)
      page2_xpath_classless_link_elements = page2_doc.xpath(page2_classless_masked_xpath)
      page2_xpath_classless_links = page2_xpath_classless_link_elements.filter_map do |element|
        populate_link_title(
          html_element_to_link(
            element, page2.fetch_uri, page2_doc, page2_classes_by_xpath, nil, logger, true, true
          ),
          page1_extraction.title_relative_xpaths
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
      is_overlap_matching = feed_entry_links.subsequence_match(page2_xpath_curis, page1_size, curi_eq_cfg)
      next unless is_overlap_matching

      page1_entry_links = page1_xpath_links
      page2_entry_links = page2_xpath_links
      best_classless_masked_xpath = page2_classless_masked_xpath
      best_title_relative_xpaths = page1_extraction.title_relative_xpaths
      page1_log_str = join_log_lines(page1_extraction.log_lines)
      page2_log_lines << "#{page2_entry_links.length} links"
      page2_log_str = join_log_lines(page2_log_lines)
      best_xpath_extra = "page1_xpath: #{page1_masked_xpath}#{page1_log_str}<br>page2_xpath: #{page2_classless_masked_xpath}#{page2_log_str}"
      page_sizes = [page1_size, page2_xpath_links.length]
      logger.info("XPath looks good for page 1: #{page1_masked_xpath}#{page1_log_str}")
      logger.info("XPath looks good for page 2: #{page2_classless_masked_xpath}#{page2_log_str}")
      break
    end
  end

  if page2_entry_links.nil?
    logger.info("Couldn't find an xpath matching page 1 and page 2")
    return nil
  end

  entry_links = page1_entry_links + page2_entry_links
  unless link_to_page3
    logger.info("Best count: #{entry_links.length} with 2 pages of #{page_sizes}")
    #noinspection RubyNilAnalysis
    page_size_counts = page_sizes.each_with_object(Hash.new(0)) { |size, counts| counts[size] += 1 }
    return PagedResult.new(
      main_link: page2_state.main_link,
      pattern: "paged_last",
      links: entry_links,
      speculative_count: entry_links.count,
      count: entry_links.count,
      extra: "page_count: 2<br>page_sizes: #{page_size_counts}<br>#{best_xpath_extra}<br>last_page:<a href=\"#{page2.fetch_uri}\">#{page2.curi}</a><br>paging_pattern: #{paging_pattern}"
    )
  end

  known_entry_curis_set = entry_links
    .map(&:curi)
    .to_canonical_uri_set(curi_eq_cfg)

  PartialPagedResult.new(
    main_link: page2_state.main_link,
    link_to_next_page: link_to_page3,
    next_page_number: 3,
    links: entry_links,
    speculative_count: entry_links.count + 1,
    count: nil,
    paged_state: NextPageState.new(
      paging_pattern: paging_pattern,
      page_number: 3,
      known_entry_curis_set: known_entry_curis_set,
      classless_masked_xpath: best_classless_masked_xpath,
      title_relative_xpaths: best_title_relative_xpaths,
      xpath_extra: best_xpath_extra,
      page_sizes: page_sizes,
      page1: page2_state.page1,
      page1_links: page2_state.page1_links,
      main_link: page2_state.main_link
    )
  )
end

def try_extract_next_page(page, paged_result, feed_entry_links, curi_eq_cfg, logger)
  entry_links = paged_result.links
  paged_state = paged_result.paged_state
  paging_pattern = paged_state.paging_pattern
  page_number = paged_state.page_number
  known_entry_curis_set = paged_state.known_entry_curis_set
  classless_masked_xpath = paged_state.classless_masked_xpath
  title_relative_xpaths = paged_state.title_relative_xpaths

  logger.info("Possible page #{page_number}: #{page.curi}")

  page_classes_by_xpath = {}
  page_xpath_link_elements = page.document.xpath(classless_masked_xpath)
  page_xpath_links = page_xpath_link_elements.filter_map do |element|
    populate_link_title(
      html_element_to_link(
        element, page.fetch_uri, page.document, page_classes_by_xpath, nil, logger, true, true
      ),
      title_relative_xpaths
    )
  end

  if page_xpath_links.empty?
    logger.info("XPath doesn't work for page #{page_number}: #{classless_masked_xpath}")
    return nil
  end

  page_known_curis = page_xpath_links
    .map(&:curi)
    .filter { |page_uri| known_entry_curis_set.include?(page_uri) }
  unless page_known_curis.empty?
    logger.info("Page #{page_number} has known links: #{page_known_curis}")
    return nil
  end

  page_entry_curis = page_xpath_links.map(&:curi)
  is_overlap_matching = feed_entry_links.subsequence_match(page_entry_curis, entry_links.length, curi_eq_cfg)
  unless is_overlap_matching
    logger.info("Page #{page_number} doesn't overlap with feed")
    logger.info("Page urls: #{page_entry_curis.map(&:to_s)}")
    logger.info("Feed urls (offset #{entry_links.length}): #{feed_entry_links}")
    return nil
  end

  page_links = extract_links(
    page.document, page.fetch_uri, [page.fetch_uri.host], nil, logger, true, false
  )
  next_page_number = page_number + 1
  link_to_next_page = find_link_to_next_page(
    page_links, page, curi_eq_cfg, next_page_number, paging_pattern, logger
  )
  if link_to_next_page == :multiple
    logger.info("Found multiple links to the next page, can't decide")
    return nil
  end

  next_entry_links = entry_links + page_xpath_links
  next_known_entry_curis_set = known_entry_curis_set.merge(page_xpath_links.map(&:curi))
  page_sizes = paged_state.page_sizes + [page_xpath_links.length]

  if link_to_next_page
    PartialPagedResult.new(
      main_link: paged_state.main_link,
      link_to_next_page: link_to_next_page,
      next_page_number: next_page_number,
      links: next_entry_links,
      speculative_count: next_entry_links.count + 1,
      count: nil,
      paged_state: NextPageState.new(
        paging_pattern: paging_pattern,
        page_number: next_page_number,
        known_entry_curis_set: next_known_entry_curis_set,
        classless_masked_xpath: classless_masked_xpath,
        title_relative_xpaths: title_relative_xpaths,
        xpath_extra: paged_state.xpath_extra,
        page_sizes: page_sizes,
        page1: paged_state.page1,
        page1_links: paged_state.page1_links,
        main_link: paged_state.main_link
      )
    )
  else
    page_count = page_number
    if paging_pattern == :blogger
      first_page_links_to_last_page = false
    else
      first_page_links_to_last_page = !!find_link_to_next_page(
        paged_state.page1_links, paged_state.page1, curi_eq_cfg, page_count, paging_pattern, logger
      )
    end

    logger.info("Best count: #{next_entry_links.length} with #{page_count} pages of #{page_sizes}")
    page_size_counts = page_sizes.each_with_object(Hash.new(0)) { |size, counts| counts[size] += 1 }

    PagedResult.new(
      main_link: paged_state.main_link,
      pattern: first_page_links_to_last_page ? "paged_last" : "paged_next",
      links: next_entry_links,
      speculative_count: next_entry_links.count,
      count: next_entry_links.count,
      extra: "page_count: #{page_count}<br>page_sizes: #{page_size_counts}<br>#{paged_state.xpath_extra}<br>last_page: <a href=\"#{page.fetch_uri}\">#{page.curi}</a><br>paging_pattern: #{paging_pattern}"
    )
  end
end

BLOGGER_QUERY_REGEX = /updated-max=([^&]+)/

def find_link_to_page2(current_page_links, current_page, feed_generator, curi_eq_cfg, logger)
  blogger_next_page_links = current_page_links.filter do |link|
    link.curi.trimmed_path == "/search" &&
      link.uri.query &&
      BLOGGER_QUERY_REGEX.match(link.uri.query)
  end

  if feed_generator == :blogger && !blogger_next_page_links.empty?
    links_to_page2 = blogger_next_page_links
    if links_to_page2
      .map(&:curi)
      .to_canonical_uri_set(curi_eq_cfg)
      .length > 1

      logger.info("Page #{current_page.curi} has multiple page 2 links: #{links_to_page2}")
      return nil
    end

    return {
      link: links_to_page2.first,
      is_certain: true,
      paging_pattern: :blogger
    }
  end

  link_to_page2_path_regex = Regexp.new("/(?:index-?2|page/?2)[^/^\\d]*$")
  is_certain = true
  is_path_match = true
  links_to_page2 = current_page_links.filter do |link|
    link.curi.host == current_page.curi.host && link_to_page2_path_regex.match?(link.curi.trimmed_path)
  end

  link_to_page2_query_regex = /([^?^&]*page=)2(?:&|$)/
  if links_to_page2.empty?
    is_path_match = false
    links_to_page2 = current_page_links.filter do |link|
      link.curi.host == current_page.curi.host && link_to_page2_query_regex.match?(link.curi.query)
    end
  end

  probable_link_to_page2_path_regex = Regexp.new("/2$")
  if links_to_page2.empty?
    is_certain = false
    is_path_match = true
    links_to_page2 = current_page_links.filter do |link|
      link.curi.host == current_page.curi.host &&
        probable_link_to_page2_path_regex.match?(link.curi.trimmed_path)
    end
    return nil if links_to_page2.empty?

    logger.info("Did not find certain links to page to but found some probable ones: #{links_to_page2.map(&:curi).map(&:to_s)}")
  end

  if links_to_page2
    .map(&:curi)
    .to_canonical_uri_set(curi_eq_cfg)
    .length > 1

    logger.info("Page #{current_page.curi} has multiple page 2 links: #{links_to_page2}")
    return nil
  end

  link = links_to_page2.first
  if is_path_match
    page_number_index = link.curi.trimmed_path.rindex('2')
    path_template = link.curi.trimmed_path[...page_number_index] +
      '%d' +
      link.curi.trimmed_path[(page_number_index + 1)..]

    {
      link: link,
      is_certain: is_certain,
      paging_pattern: {
        host: link.curi.host,
        path_template: path_template,
        is_certain: is_certain
      },
    }
  else
    query_template = link_to_page2_query_regex.match(link.curi.query)[1] + '%d'

    {
      link: link,
      is_certain: is_certain,
      paging_pattern: {
        host: link.curi.host,
        path: link.curi.trimmed_path,
        query_template: query_template,
        is_certain: is_certain
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
      (current_date_match = BLOGGER_QUERY_REGEX.match(current_page.fetch_uri.query))

    links_to_next_page = current_page_links.filter do |link|
      !link.xpath.start_with?("/html[1]/head[1]") &&
        link.curi.trimmed_path == "/search" &&
        link.uri.query &&
        (next_date_match = BLOGGER_QUERY_REGEX.match(link.uri.query)) &&
        next_date_match[1] < current_date_match[1]
    end
  else
    if paging_pattern[:path_template]
      expected_path = paging_pattern[:path_template] % next_page_number
      links_to_next_page = current_page_links.filter do |link|
        link.curi.host == paging_pattern[:host] && link.curi.trimmed_path == expected_path
      end
    else
      expected_query_substring = paging_pattern[:query_template] % next_page_number
      links_to_next_page = current_page_links.filter do |link|
        link.curi.host == paging_pattern[:host] && link.curi.query&.include?(expected_query_substring)
      end
    end
  end

  if links_to_next_page
    .map(&:curi)
    .to_canonical_uri_set(curi_eq_cfg)
    .length > 1

    logger.info("Page #{next_page_number - 1} #{current_page.curi} has multiple page #{next_page_number} links: #{links_to_next_page}")
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