def get_extractions_by_masked_xpath_by_star_count(
  page_links, feed_entry_links, feed_entry_curis_set, curi_eq_cfg, almost_match_threshold, logger
)
  star_count_xpath_names = [
    [1, :xpath],
    [2, :class_xpath],
    [3, :class_xpath]
  ]

  extractions_by_masked_xpath_by_star_count = {}
  star_count_xpath_names.each do |star_count, xpath_name|
    links_by_masked_xpath = group_links_by_masked_xpath(
      page_links, feed_entry_curis_set, xpath_name, star_count
    )
    logger.log("Masked xpaths with #{star_count} stars: #{links_by_masked_xpath.length}")

    extractions_by_masked_xpath = links_by_masked_xpath.to_h do |masked_xpath, masked_xpath_links|
      [
        masked_xpath,
        get_masked_xpath_extraction(
          masked_xpath, masked_xpath_links, star_count, feed_entry_links, feed_entry_curis_set, curi_eq_cfg,
          almost_match_threshold, logger
        )
      ]
    end

    extractions_by_masked_xpath_by_star_count[star_count] = extractions_by_masked_xpath
  end

  extractions_by_masked_xpath_by_star_count
end

XpathTreeNode = Struct.new(:xpath_segments, :children, :parent, :is_link, :is_feed_link)

def group_links_by_masked_xpath(page_links, feed_entry_curis_set, xpath_name, star_count)
  def xpath_to_segments(xpath)
    xpath.split("/")[1..].map do |token|
      match = token.match(/^([^\[]+)\[(\d+)\]$/)
      raise "XPath token match failed: #{link_xpath}, #{token}" unless match && match[1] && match[2]
      [match[1], match[2].to_i]
    end
  end

  page_link_xpaths_segments_is_feed_link = page_links.map do |page_link|
    [
      xpath_to_segments(page_link[xpath_name]),
      feed_entry_curis_set.include?(page_link.curi)
    ]
  end

  def build_xpath_tree(xpaths_segments_is_feed_link)
    xpath_tree = XpathTreeNode.new([], {}, nil, false)
    xpaths_segments_is_feed_link.each do |xpath_segments, is_feed_link|
      current_node = xpath_tree
      xpath_segments.each_with_index do |segment, index|
        is_link = index == xpath_segments.length - 1
        if current_node.children.key?(segment)
          current_node.children[segment].is_link ||= is_link
          current_node.children[segment].is_feed_link ||= is_link && is_feed_link
        else
          child_xpath_segments = current_node.xpath_segments + [segment]
          current_node.children[segment] =
            XpathTreeNode.new(child_xpath_segments, {}, current_node, is_link, is_link && is_feed_link)
        end
        current_node = current_node.children[segment]
      end
    end
    xpath_tree
  end

  xpath_tree = build_xpath_tree(page_link_xpaths_segments_is_feed_link)

  def traverse_xpath_tree_feed_links(xpath_tree_node, &block)
    xpath_tree_node.children.each_value do |child_node|
      if child_node.is_feed_link
        yield child_node
      end
      traverse_xpath_tree_feed_links(child_node, &block)
    end
  end

  def add_masked_xpaths_segments(
    start_node, start_xpath_segments_suffix, stars_remaining, masked_xpaths_segments
  )
    ancestor_node = start_node.parent
    xpath_segments_suffix = start_xpath_segments_suffix
    while ancestor_node
      child_tag, child_index = start_node.xpath_segments[ancestor_node.xpath_segments.length]
      masked_xpath_segments = ancestor_node.xpath_segments + [[child_tag, :star]] + xpath_segments_suffix
      if stars_remaining > 1 || !masked_xpaths_segments.include?(masked_xpath_segments)
        found_another_link = false
        ancestor_node.children.each do |child_key, current_child_node|
          next unless child_key[0] == child_tag && child_key[1] != child_index
          xpath_segments_remaining = xpath_segments_suffix
          loop do
            found_another_link = true if xpath_segments_remaining.empty? && current_child_node.is_link
            break if xpath_segments_remaining.empty?

            xpath_key = xpath_segments_remaining[0]
            current_child_node = current_child_node
              .children
              .find { |key, _| key[0] == xpath_key[0] && (key[1] == xpath_key[1] || xpath_key[1] == :star) }
              &.last
            break unless current_child_node

            xpath_segments_remaining = xpath_segments_remaining[1..]
          end
          break if found_another_link
        end

        if found_another_link
          if stars_remaining == 1
            masked_xpaths_segments << masked_xpath_segments
          else
            next_xpath_segments_suffix = [[child_tag, :star]] + xpath_segments_suffix
            add_masked_xpaths_segments(
              ancestor_node, next_xpath_segments_suffix, stars_remaining - 1, masked_xpaths_segments
            )
          end
        end
      end

      xpath_segments_suffix = [start_node.xpath_segments[ancestor_node.xpath_segments.length]] +
        xpath_segments_suffix
      ancestor_node = ancestor_node.parent
    end
  end

  page_feed_masked_xpaths_segments = Set.new
  traverse_xpath_tree_feed_links(xpath_tree) do |link_node|
    add_masked_xpaths_segments(
      link_node, [], star_count, page_feed_masked_xpaths_segments
    )
  end

  masked_xpath_tree = build_xpath_tree(
    page_feed_masked_xpaths_segments.map{ |xpath_segments| [xpath_segments, false] }
  )

  def masked_xpath_from_segments(xpath_segments)
    xpath_segments
      .map { |segment| "/#{segment[0]}[#{segment[1] == :star ? '*' : segment[1]}]" }
      .join
  end

  def add_links_matching_subtree(current_node, link, remaining_link_xpath_segments, links_by_masked_xpath)
    if remaining_link_xpath_segments.empty? && current_node.is_link
      masked_xpath = masked_xpath_from_segments(current_node.xpath_segments)
      links_by_masked_xpath[masked_xpath] = [] unless links_by_masked_xpath.key?(masked_xpath)
      links_by_masked_xpath[masked_xpath] << link
    end
    next_segment = remaining_link_xpath_segments[0]
    current_node.children.each do |key, child_node|
      next unless key[0] == next_segment[0] && (key[1] == next_segment[1] || key[1] == :star)

      add_links_matching_subtree(child_node, link, remaining_link_xpath_segments[1..], links_by_masked_xpath)
    end
  end

  links_by_masked_xpath = {}
  page_links.each do |page_link|
    page_link_xpath_segments = xpath_to_segments(page_link[xpath_name])
    add_links_matching_subtree(masked_xpath_tree, page_link, page_link_xpath_segments, links_by_masked_xpath)
  end

  links_by_masked_xpath
end


LinksExtraction = Struct.new(:links, :curis, :curis_set, :has_duplicates)
DatesExtraction = Struct.new(:dates, :are_sorted, :are_reverse_sorted)
MaskedXpathExtraction = Struct.new(
  :links_extraction, :log_lines, :markup_dates_extraction, :medium_markup_dates,
  :almost_markup_dates_extraction, :maybe_url_dates
)

def get_masked_xpath_extraction(
  masked_xpath, links, star_count, feed_entry_links, feed_entry_curis_set, curi_eq_cfg,
  almost_match_threshold, logger
)
  collapsed_links = []
  links.length.times do |index|
    if index == 0 ||
      !canonical_uri_equal?(links[index].curi, links[index - 1].curi, curi_eq_cfg)

      collapsed_links << links[index]
    end
  end

  log_lines = []
  if links.length != collapsed_links.length
    log_lines << "collapsed #{links.length} -> #{collapsed_links.length}"
  end

  filtered_links = collapsed_links
  markup_dates_extraction = DatesExtraction.new(nil, nil, nil)
  medium_markup_dates = nil
  almost_markup_dates_extraction = DatesExtraction.new(nil, nil, nil)

  links_matching_feed = collapsed_links
    .filter { |link| feed_entry_curis_set.include?(link.curi) }
  unique_links_matching_feed_count = links_matching_feed
    .map(&:curi)
    .to_canonical_uri_set(curi_eq_cfg)
    .length
  threshold_to_have_some_dates = [almost_match_threshold, feed_entry_links.length - 1].min

  if unique_links_matching_feed_count >= threshold_to_have_some_dates
    last_star_index = masked_xpath.rindex("*")
    distance_to_top_parent = masked_xpath[last_star_index..].count("/")
    relative_xpath_to_top_parent = "/.." * distance_to_top_parent

    if unique_links_matching_feed_count >= almost_match_threshold
      matching_maybe_markup_dates = extract_maybe_markup_dates(
        collapsed_links, links_matching_feed, distance_to_top_parent, relative_xpath_to_top_parent,
        false, logger
      )

      if matching_maybe_markup_dates
        filtered_links, matching_markup_dates = collapsed_links
          .zip(matching_maybe_markup_dates)
          .filter { |_, date| date != nil }
          .transpose
        if filtered_links.length != links.length
          log_lines << "filtered by dates #{collapsed_links.length} -> #{filtered_links.length}"
        end

        if star_count >= 2
          matching_are_sorted = matching_markup_dates
            .each_cons(2)
            .all? { |date1, date2| date1 >= date2 }
          matching_are_reverse_sorted = matching_markup_dates
            .each_cons(2)
            .all? { |date1, date2| date1 <= date2 }
        else
          # Trust the ordering of links more than dates
          matching_are_sorted = nil
          matching_are_reverse_sorted = nil
        end

        if unique_links_matching_feed_count == feed_entry_links.length
          markup_dates_extraction = DatesExtraction.new(
            matching_markup_dates, matching_are_sorted, matching_are_reverse_sorted
          )
        else
          almost_markup_dates_extraction = DatesExtraction.new(
            matching_markup_dates, matching_are_sorted, matching_are_reverse_sorted
          )
        end
      end
    end

    if unique_links_matching_feed_count == feed_entry_links.length - 1
      maybe_medium_markup_dates = extract_maybe_markup_dates(
        collapsed_links, links_matching_feed, distance_to_top_parent, relative_xpath_to_top_parent,
        true, logger
      )

      if maybe_medium_markup_dates && maybe_medium_markup_dates.all? { |date| date != nil }
        medium_markup_dates = maybe_medium_markup_dates
      end
    end
  end

  curis = filtered_links.map(&:curi)
  curis_set = curis.to_canonical_uri_set(curi_eq_cfg)
  has_duplicates = curis.length != curis_set.length
  links_extraction = LinksExtraction.new(filtered_links, curis, curis_set, has_duplicates)

  maybe_url_dates = filtered_links.map do |link|
    next unless link.curi.path

    date_match = link.curi.path.match(/\/(\d{4})\/(\d{2})\/(\d{2})/)
    next unless date_match

    begin
      year = date_match[1].to_i
      month = date_match[2].to_i
      day = date_match[3].to_i
      Date.new(year, month, day)
    rescue
      next
    end
  end

  MaskedXpathExtraction.new(
    links_extraction, log_lines, markup_dates_extraction, medium_markup_dates, almost_markup_dates_extraction,
    maybe_url_dates
  )
end

def extract_maybe_markup_dates(
  links, links_matching_feed, distance_to_top_parent, relative_xpath_to_top_parent, guess_year, logger
)
  date_relative_xpaths_sources = []
  links_matching_feed.each_with_index do |link, index|
    link_top_parent = link.element
    distance_to_top_parent.times do
      link_top_parent = link_top_parent.parent
    end
    link_top_parent_path = link_top_parent.path
    link_date_relative_xpaths_sources = []
    link_top_parent.traverse do |element|
      date_source = try_extract_element_date(element, guess_year)
      next unless date_source

      date_relative_xpath = (relative_xpath_to_top_parent + element.path[link_top_parent_path.length..])
        .delete_prefix("/")
      relative_xpath_source = { xpath: date_relative_xpath, source: date_source[:source] }
      link_date_relative_xpaths_sources << relative_xpath_source if date_source[:date]
    end

    if index == 0
      date_relative_xpaths_sources = link_date_relative_xpaths_sources
    else
      link_full_date_relative_xpaths_sources_set = link_date_relative_xpaths_sources.to_set
      date_relative_xpaths_sources
        .filter! { |xpath_source| link_full_date_relative_xpaths_sources_set.include?(xpath_source) }
    end
  end

  date_relative_xpaths_from_time = date_relative_xpaths_sources
    .filter_map { |xpath_source| xpath_source[:source] == :time ? xpath_source[:xpath] : nil }
  if date_relative_xpaths_sources.length == 1
    date_relative_xpath = date_relative_xpaths_sources.first[:xpath]
  elsif date_relative_xpaths_from_time.length == 1
    date_relative_xpath = date_relative_xpaths_from_time.first
  else
    return nil
  end

  maybe_dates = links.map do |link|
    link_dates = link
      .element
      .xpath(date_relative_xpath)
      .to_a
      .filter_map { |element| try_extract_element_date(element, guess_year) }
      .map { |date_source| date_source[:date] }
    next if link_dates.empty?

    if link_dates.length > 1
      logger.log("Multiple dates found for #{link.xpath} + #{date_relative_xpath}: #{link_dates}")
      next
    end

    link_dates.first
  end

  maybe_dates
end
