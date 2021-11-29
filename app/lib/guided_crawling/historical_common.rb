require 'set'
require_relative 'title'

HistoricalResult = Struct.new(:main_link, :pattern, :links, :count, :extra, keyword_init: true)

def get_extractions_by_masked_xpath_by_star_count(
  page_links, feed_entry_links, feed_entry_curis_titles_map, curi_eq_cfg, almost_match_threshold, logger
)
  star_count_xpath_names = [
    [1, :xpath],
    [2, :class_xpath],
    [3, :class_xpath]
  ]

  extractions_by_masked_xpath_by_star_count = {}
  star_count_xpath_names.each do |star_count, xpath_name|
    link_groupings_by_masked_xpath = group_links_by_masked_xpath(
      page_links, feed_entry_curis_titles_map, curi_eq_cfg, xpath_name, star_count
    )
    logger.info("Masked xpaths with #{star_count} stars: #{link_groupings_by_masked_xpath.length}")

    extractions_by_masked_xpath = link_groupings_by_masked_xpath.to_h do |masked_xpath, link_grouping|
      [
        masked_xpath,
        get_masked_xpath_extraction(
          masked_xpath, link_grouping, star_count, feed_entry_links, feed_entry_curis_titles_map, curi_eq_cfg,
          almost_match_threshold
        )
      ]
    end

    extractions_by_masked_xpath_by_star_count[star_count] = extractions_by_masked_xpath
  end

  extractions_by_masked_xpath_by_star_count
end

XpathTreeNode = Struct.new(:xpath_segments, :children, :parent, :is_link, :is_feed_link)

def pretty_print_xpath_tree_node(xpath_tree_node, depth = 0)
  lines = []
  tab = "  " * depth
  lines << "#{tab}xpath_segments: #{xpath_tree_node.xpath_segments}"
  lines << "#{tab}children: ["
  xpath_tree_node.children.each do |key, value|
    lines << "#{tab}[#{key}]:"
    lines.push(*pretty_print_xpath_tree_node(value, depth + 2))
  end
  lines << "#{tab}]"
  lines << "#{tab}parent: #{xpath_tree_node.parent ? "(parent)" : "(nil)"}"
  lines << "#{tab}is_link: #{xpath_tree_node.is_link}"
  lines << "#{tab}is_feed_link: #{xpath_tree_node.is_feed_link}"
  lines.join("\n")
end

MaskedXpathLinksGrouping = Struct.new(:links, :title_relative_xpaths, :xpath_name, :log_lines)

def group_links_by_masked_xpath(page_links, feed_entry_curis_titles_map, curi_eq_cfg, xpath_name, star_count)
  def xpath_to_segments(xpath)
    xpath.split("/")[1..].map do |token|
      match = token.match(/^([^\[]+)\[(\d+)\]$/)
      raise "XPath token match failed: #{xpath}, #{token}" unless match && match[1] && match[2]
      [match[1], match[2].to_i]
    end
  end

  page_links_xpath_segments = page_links.map { |page_link| xpath_to_segments(page_link[xpath_name]) }

  page_link_xpaths_segments_is_feed_link = page_links
    .zip(page_links_xpath_segments)
    .map do |page_link, xpath_segments|
    [
      xpath_segments,
      feed_entry_curis_titles_map.include?(page_link.curi)
    ]
  end

  def build_xpath_tree(xpaths_segments_is_feed_link)
    xpath_tree = XpathTreeNode.new([], {}, nil, false, false)
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
    start_node, start_xpath_segments_suffix, stars_remaining, page_feed_masked_xpaths_segments
  )
    ancestor_node = start_node.parent
    xpath_segments_suffix = start_xpath_segments_suffix
    while ancestor_node
      child_tag, child_index = start_node.xpath_segments[ancestor_node.xpath_segments.length]
      masked_xpath_segments = ancestor_node.xpath_segments + [[child_tag, :star]] + xpath_segments_suffix
      if stars_remaining > 1 || !page_feed_masked_xpaths_segments.include?(masked_xpath_segments)
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
            page_feed_masked_xpaths_segments << masked_xpath_segments
          else
            next_xpath_segments_suffix = [[child_tag, :star]] + xpath_segments_suffix
            add_masked_xpaths_segments(
              ancestor_node, next_xpath_segments_suffix, stars_remaining - 1, page_feed_masked_xpaths_segments
            )
          end
        end
      end

      xpath_segments_suffix.prepend(start_node.xpath_segments[ancestor_node.xpath_segments.length])
      ancestor_node = ancestor_node.parent
    end
  end

  page_feed_masked_xpaths_segments = Set.new
  traverse_xpath_tree_feed_links(xpath_tree) do |link_node|
    add_masked_xpaths_segments(link_node, [], star_count, page_feed_masked_xpaths_segments)
  end

  masked_xpath_tree = build_xpath_tree(
    page_feed_masked_xpaths_segments.map { |xpath_segments| [xpath_segments, false] }
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
  page_links.zip(page_links_xpath_segments).each do |page_link, xpath_segments|
    add_links_matching_subtree(masked_xpath_tree, page_link, xpath_segments, links_by_masked_xpath)
  end

  filtered_links_by_masked_xpath = links_by_masked_xpath
    .filter do |_, masked_xpath_links|
    masked_xpath_links.map(&:curi).to_canonical_uri_set(curi_eq_cfg).length > 1
  end
    .to_h

  masked_xpath_link_groupings = []
  filtered_links_by_masked_xpath.each do |masked_xpath, masked_xpath_links|
    top_parent_distance, top_parent_relative_xpath = get_top_parent_distance_relative_xpath(masked_xpath)
    masked_xpath_links_matching_feed = masked_xpath_links
      .filter { |link| feed_entry_curis_titles_map.include?(link.curi) }
    log_lines = []
    title_relative_xpaths = extract_title_relative_xpaths(
      masked_xpath_links_matching_feed, feed_entry_curis_titles_map, curi_eq_cfg, top_parent_distance,
      top_parent_relative_xpath, log_lines
    )
    masked_xpath_titled_links = masked_xpath_links
      .map { |masked_xpath_link| populate_link_title(masked_xpath_link, title_relative_xpaths) }
    masked_xpath_link_groupings << [
      masked_xpath,
      MaskedXpathLinksGrouping.new(masked_xpath_titled_links, title_relative_xpaths, xpath_name, log_lines)
    ]
  end

  # Prioritize xpaths with maximum number of original link titles matching feed, then discovered link titles
  # matching feed
  ordered_masked_xpath_link_groupings = masked_xpath_link_groupings.sort_by do |_, link_grouping|
    [
      -link_grouping.links.count do |masked_xpath_link|
        feed_entry_curis_titles_map[masked_xpath_link.curi] &&
          equalize_title(get_element_title(masked_xpath_link.element)) ==
            feed_entry_curis_titles_map[masked_xpath_link.curi].equalized_value
      end,
      -link_grouping.links.count do |masked_xpath_link|
        feed_entry_curis_titles_map[masked_xpath_link.curi] &&
          masked_xpath_link.title &&
          masked_xpath_link.title.equalized_value ==
            feed_entry_curis_titles_map[masked_xpath_link.curi].equalized_value
      end
    ]
  end

  ordered_link_groupings_by_masked_xpath = {}
  ordered_masked_xpath_link_groupings.each do |masked_xpath, link_grouping|
    ordered_link_groupings_by_masked_xpath[masked_xpath] = link_grouping
  end

  ordered_link_groupings_by_masked_xpath
end

LinksExtraction = Struct.new(:links, :curis, :curis_set, :has_duplicates)
DatesExtraction = Struct.new(:dates, :are_sorted, :are_reverse_sorted)
MaskedXpathExtraction = Struct.new(
  :links_extraction, :unfiltered_links, :log_lines, :markup_dates_extraction, :medium_markup_dates,
  :almost_markup_dates_extraction, :some_markup_dates, :maybe_url_dates, :title_relative_xpaths, :xpath_name
)

def get_masked_xpath_extraction(
  masked_xpath, link_grouping, star_count, feed_entry_links, feed_entry_curis_titles_map, curi_eq_cfg,
  almost_match_threshold
)
  links = link_grouping.links
  title_relative_xpaths = link_grouping.title_relative_xpaths
  xpath_name = link_grouping.xpath_name
  log_lines = link_grouping.log_lines.clone

  collapsed_links = []
  links.length.times do |index|
    if index == 0 || !canonical_uri_equal?(links[index].curi, links[index - 1].curi, curi_eq_cfg)
      collapsed_links << links[index]
    else
      # Merge titles if multiple equal links in a row
      last_link = collapsed_links[-1]
      if last_link.title && links[index].title
        new_title_value = last_link.title.value + links[index].title.value
        if last_link.title.source == links[index].title.source
          new_title_source = last_link.title.source
        else
          new_title_source = :collapsed
        end
        new_title = create_link_title(new_title_value, new_title_source)
      elsif last_link.title
        new_title = last_link.title
      else
        new_title = links[index].title
      end

      collapsed_links[-1] = link_set_title(last_link, new_title)
    end
  end

  if links.length != collapsed_links.length
    log_lines << "collapsed #{links.length} -> #{collapsed_links.length}"
  end

  filtered_links = collapsed_links
  markup_dates_extraction = DatesExtraction.new(nil, nil, nil)
  medium_markup_dates = nil
  almost_markup_dates_extraction = DatesExtraction.new(nil, nil, nil)
  some_markup_dates = nil

  links_matching_feed = collapsed_links
    .filter { |link| feed_entry_curis_titles_map.include?(link.curi) }
  unique_links_matching_feed_count = links_matching_feed
    .map(&:curi)
    .to_canonical_uri_set(curi_eq_cfg)
    .length

  distance_to_top_parent, relative_xpath_to_top_parent = get_top_parent_distance_relative_xpath(masked_xpath)

  matching_maybe_markup_dates = extract_maybe_markup_dates(
    collapsed_links, links_matching_feed, distance_to_top_parent, relative_xpath_to_top_parent, false,
    log_lines
  )

  if matching_maybe_markup_dates
    if unique_links_matching_feed_count >= almost_match_threshold
      filtered_links, matching_markup_dates = collapsed_links
        .zip(matching_maybe_markup_dates)
        .filter { |_, maybe_date| maybe_date != nil }
        .transpose
      if filtered_links.length != links.length
        log_lines << "filtered by dates #{collapsed_links.length} -> #{filtered_links.length}"
      end
    elsif matching_maybe_markup_dates.all? { |maybe_date| maybe_date != nil }
      matching_markup_dates = matching_maybe_markup_dates
    else
      matching_markup_dates = nil
    end

    if matching_markup_dates
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
      elsif unique_links_matching_feed_count >= almost_match_threshold
        almost_markup_dates_extraction = DatesExtraction.new(
          matching_markup_dates, matching_are_sorted, matching_are_reverse_sorted
        )
      end

      some_markup_dates = matching_markup_dates
    end
  end

  if unique_links_matching_feed_count == feed_entry_links.length - 1
    maybe_medium_markup_dates = extract_maybe_markup_dates(
      collapsed_links, links_matching_feed, distance_to_top_parent, relative_xpath_to_top_parent, true,
      log_lines
    )

    if maybe_medium_markup_dates && maybe_medium_markup_dates.all? { |date| date != nil }
      medium_markup_dates = maybe_medium_markup_dates
    end
  end

  curis = filtered_links.map(&:curi)
  curis_set = curis.to_canonical_uri_set(curi_eq_cfg)
  has_duplicates = curis.length != curis_set.length
  links_extraction = LinksExtraction.new(filtered_links, curis, curis_set, has_duplicates)

  maybe_url_dates = filtered_links.map do |link|
    next unless link.curi.path

    date_match = link.curi.path.match(/\/(\d{4})\/(\d{2})\/(\d{2})\//)
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
    links_extraction, collapsed_links, log_lines, markup_dates_extraction, medium_markup_dates,
    almost_markup_dates_extraction, some_markup_dates, maybe_url_dates, title_relative_xpaths, xpath_name
  )
end

def get_top_parent_distance_relative_xpath(masked_xpath)
  last_star_index = masked_xpath.rindex("*")
  distance_to_top_parent = masked_xpath[last_star_index..].count("/")
  if distance_to_top_parent == 0
    relative_xpath_to_top_parent = ""
  else
    relative_xpath_to_top_parent = ".." + "/.." * (distance_to_top_parent - 1)
  end
  [distance_to_top_parent, relative_xpath_to_top_parent]
end

def extract_maybe_markup_dates(
  links, links_matching_feed, distance_to_top_parent, relative_xpath_to_top_parent, guess_year, log_lines
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
    dates = link
      .element
      .xpath(date_relative_xpath)
      .to_a
      .filter_map { |element| try_extract_element_date(element, guess_year) }
      .map { |date_source| date_source[:date] }
    next if dates.empty?

    if dates.length > 1
      log_lines << "multiple dates for #{date_relative_xpath} and guess_year=#{guess_year}: #{dates.map(&:to_s)}"
      next
    end

    dates.first
  end

  maybe_dates
end

class TitleRelativeXpath
  def initialize(xpath, kind)
    @xpath = xpath
    @kind = kind
  end

  attr_reader :xpath, :kind

  def to_s
    "['#{@xpath}', :#{@kind}]"
  end
end

def extract_title_relative_xpaths(
  links_matching_feed, feed_entry_curis_titles_map, curi_eq_cfg, top_parent_distance,
  top_parent_relative_xpath, log_lines
)
  link_title_values = links_matching_feed.map { |link| get_element_title(link.element) }
  eq_link_title_values = link_title_values.map { |title_value| equalize_title(title_value) }
  feed_titles = links_matching_feed.map { |link| feed_entry_curis_titles_map[link.curi] }

  # See if the link inner text just matches
  link_titles_not_exactly_matching = links_matching_feed
    .zip(eq_link_title_values, feed_titles)
    .filter do |_, eq_link_title_value, feed_title|
    !(feed_title && eq_link_title_value == feed_title.equalized_value)
  end

  def get_allowed_mismatch_count(links_count)
    if links_count <= 8
      0
    elsif links_count <= 52
      2
    else
      3
    end
  end

  # Title relative xpaths are discovered before collapsing links. If a link has multiple parts, the title
  # of each part won't match feed, but we should count it as one mismatch and not multiple.
  unique_mismatch_count = link_titles_not_exactly_matching
    .map(&:first)
    .map(&:curi)
    .to_canonical_uri_set(curi_eq_cfg)
    .length
  unique_links_count = links_matching_feed
    .map(&:curi)
    .to_canonical_uri_set(curi_eq_cfg)
    .length

  allowed_mismatch_count = get_allowed_mismatch_count(unique_links_count)
  if unique_mismatch_count <= allowed_mismatch_count
    almost_log = unique_mismatch_count == 0 ? "exactly" : "almost"
    log_lines << "titles #{almost_log} matching"
    return [TitleRelativeXpath.new("", :self)]
  end

  def find_title_match(element, feed_title, child_xpath_to_skip = nil)
    return nil unless feed_title

    element.children.each do |child|
      child_title_value = get_element_title(child)
      next unless child_title_value

      child_xpath = child.path.match("/([^/]+)$")[1]
      unless child_xpath.end_with?("]")
        child_xpath += "[1]"
      end
      next if child_xpath == child_xpath_to_skip

      eq_child_title_value = equalize_title(child_title_value)
      return child_xpath if eq_child_title_value == feed_title.equalized_value

      if eq_child_title_value.include?(feed_title.equalized_value)
        grandchild_xpath = find_title_match(child, feed_title)
        return child_xpath + "/" + grandchild_xpath if grandchild_xpath
      end
    end

    nil
  end

  # See if there is a child element that matches
  titles_without_matching_children = links_matching_feed
    .zip(eq_link_title_values, feed_titles)
    .filter do |_, eq_link_title_value, feed_title|
    !(feed_title && eq_link_title_value&.include?(feed_title.equalized_value))
  end

  unique_child_mismatch_count = titles_without_matching_children
    .map(&:first)
    .map(&:curi)
    .to_canonical_uri_set(curi_eq_cfg)
    .length

  if unique_child_mismatch_count <= allowed_mismatch_count
    child_xpaths_set = Set.new
    links_matching_feed.zip(feed_titles).each do |link, feed_title|
      child_xpaths_set << find_title_match(link.element, feed_title)
    end

    child_xpaths_set.each do |child_xpath|
      next unless child_xpath

      child_xpath_title_mismatch_count = links_matching_feed
        .zip(feed_titles)
        .count do |link, feed_title|
        child_element = link.element.xpath(child_xpath).first
        !child_element || equalize_title(get_element_title(child_element)) != feed_title.equalized_value
      end

      if child_xpath_title_mismatch_count <= allowed_mismatch_count
        almost_log = child_xpath_title_mismatch_count == 0 ? "exactly" : "almost"
        log_lines << "child titles #{almost_log} matching at #{child_xpath}"
        return [TitleRelativeXpath.new(child_xpath, :child)]
      end
    end
  end

  # See if there is a neighbor element that matches
  neighbor_xpaths = Set.new
  links_matching_feed
    .zip(feed_titles)
    .each do |link, feed_title|

    link_xpath_relative_to_top_parent = link.xpath.match("(/[^/]+){#{top_parent_distance}}$")[0]
    link_top_parent = link.element
    top_parent_distance.times do
      link_top_parent = link_top_parent.parent
    end
    title_xpath_relative_to_top_parent = find_title_match(
      link_top_parent, feed_title, link_xpath_relative_to_top_parent
    )
    next unless title_xpath_relative_to_top_parent

    neighbor_xpath = top_parent_relative_xpath + "/" + title_xpath_relative_to_top_parent
    neighbor_xpaths << neighbor_xpath
  end

  only_true_positive_neighbor_xpaths = []
  neighbor_xpaths.each do |neighbor_xpath|
    are_all_neighbor_titles_matching = true
    links_matching_feed.zip(feed_titles).each do |link, feed_title|
      neighbor_element = link.element.xpath(neighbor_xpath).first
      next unless neighbor_element

      eq_neighbor_title_value = equalize_title(get_element_title(neighbor_element))
      unless feed_title && (eq_neighbor_title_value == feed_title.equalized_value)
        are_all_neighbor_titles_matching = false
        break
      end
    end

    if are_all_neighbor_titles_matching
      only_true_positive_neighbor_xpaths << TitleRelativeXpath.new(neighbor_xpath, :true_neighbor)
    end
  end

  matching_neighbor_xpaths = only_true_positive_neighbor_xpaths
  unless matching_neighbor_xpaths.empty?
    log_lines << "neighbor titles matching at #{matching_neighbor_xpaths}"
    return matching_neighbor_xpaths
  end

  log_lines << "titles not matching"
  nil
end

def populate_link_title(link, title_relative_xpaths)
  return link unless link && title_relative_xpaths

  element = link.element
  title_value = nil
  source = nil
  alternative_values_by_source = {}
  title_relative_xpaths.each do |title_relative_xpath|
    if title_relative_xpath.xpath.empty?
      title_element = element
    else
      title_element = element
        .xpath(title_relative_xpath.xpath)
        .first
    end

    next unless title_element

    if title_value
      if alternative_values_by_source.key?(title_relative_xpath)
        raise "Duplicate title relative xpath: #{title_relative_xpath}"
      end
      alternative_values_by_source[title_relative_xpath] = get_element_title(title_element)
    else
      title_value = get_element_title(title_element)
      source = title_relative_xpath
    end
  end

  return link unless title_value

  title = create_link_title(title_value, source, alternative_values_by_source)
  link_set_title(link, title)
end

def join_log_lines(log_lines)
  if log_lines.empty?
    ""
  else
    " (#{log_lines.join(", ")})"
  end
end