require 'set'
require 'time'
require_relative 'historical_common'

def try_extract_archives(
  page, page_links, page_canonical_uris_set, feed_entry_links, feed_entry_canonical_uris,
  feed_entry_canonical_uris_set, canonical_equality_cfg, min_links_count, logger
)
  return nil unless feed_entry_canonical_uris
    .count { |item_uri| page_canonical_uris_set.include?(item_uri) } >=
    almost_match_length(feed_entry_canonical_uris.length)

  logger.log("Possible archives page: #{page.canonical_uri}")
  min_links_count_one_xpath = min_links_count_two_xpaths = min_links_count
  best_page_links = nil
  best_page_canonical_uris = nil
  fewer_stars_have_dates = false
  best_star_count = nil
  did_almost_match_feed = false
  almost_match_length = nil

  logger.log("Trying xpaths with 1 star")
  historical_links_one_star = try_masked_xpath(
    page_links, feed_entry_canonical_uris, feed_entry_canonical_uris_set, canonical_equality_cfg,
    1, :xpath, best_page_canonical_uris, fewer_stars_have_dates,
    min_links_count_one_xpath, min_links_count_two_xpaths, logger
  )

  links_by_masked_xpath_one_star = historical_links_one_star[:links_by_masked_xpath]
  if historical_links_one_star[:is_full_match]
    best_page_links = historical_links_one_star
    best_star_count = "1"
    if historical_links_one_star[:is_one_xpath]
      min_links_count_one_xpath = best_page_links[:links].length + 1
    else
      min_links_count_one_xpath = best_page_links[:links].length
    end
    min_links_count_two_xpaths = best_page_links[:links].length + 1
    best_page_canonical_uris = best_page_links[:links].map(&:canonical_uri)
    fewer_stars_have_dates = best_page_links[:has_dates]
  elsif historical_links_one_star[:did_almost_match_feed]
    did_almost_match_feed = true
    unless almost_match_length && almost_match_length > historical_links_one_star[:almost_match_length]
      almost_match_length = historical_links_one_star[:almost_match_length]
    end
  end

  logger.log("Trying xpaths with 2 stars")
  historical_links_two_stars = try_masked_xpath(
    page_links, feed_entry_canonical_uris, feed_entry_canonical_uris_set, canonical_equality_cfg,
    2, :class_xpath, best_page_canonical_uris, fewer_stars_have_dates,
    min_links_count_one_xpath, min_links_count_two_xpaths, logger
  )

  links_by_masked_xpath_two_stars = historical_links_two_stars[:links_by_masked_xpath]
  if historical_links_two_stars[:is_full_match]
    best_page_links = historical_links_two_stars
    best_star_count = "2"
    if historical_links_two_stars[:is_one_xpath]
      min_links_count_one_xpath = best_page_links[:links].length + 1
    else
      min_links_count_one_xpath = best_page_links[:links].length
    end
    min_links_count_two_xpaths = best_page_links[:links].length + 1
    best_page_canonical_uris = best_page_links[:links].map(&:canonical_uri)
    fewer_stars_have_dates = best_page_links[:has_dates]
  elsif historical_links_two_stars[:did_almost_match_feed]
    did_almost_match_feed = true
    unless almost_match_length && almost_match_length > historical_links_two_stars[:almost_match_length]
      almost_match_length = historical_links_two_stars[:almost_match_length]
    end
  end

  logger.log("Trying xpaths with 3 stars")
  historical_links_three_stars = try_masked_xpath(
    page_links, feed_entry_canonical_uris, feed_entry_canonical_uris_set, canonical_equality_cfg,
    3, :class_xpath, best_page_canonical_uris, fewer_stars_have_dates,
    min_links_count_one_xpath, min_links_count_two_xpaths, logger
  )

  links_by_masked_xpath_three_stars = historical_links_three_stars[:links_by_masked_xpath]
  if historical_links_three_stars[:is_full_match]
    best_page_links = historical_links_three_stars
    best_star_count = "3"
    min_links_count_two_xpaths = best_page_links[:links].length + 1
    best_page_canonical_uris = best_page_links[:links].map(&:canonical_uri)
  elsif historical_links_three_stars[:did_almost_match_feed]
    did_almost_match_feed = true
    unless almost_match_length && almost_match_length > historical_links_three_stars[:almost_match_length]
      almost_match_length = historical_links_three_stars[:almost_match_length]
    end
  end

  logger.log("Trying xpaths with 1+1 star")
  historical_links_one_plus_one_star = try_two_masked_xpaths(
    links_by_masked_xpath_one_star, links_by_masked_xpath_one_star, feed_entry_canonical_uris,
    canonical_equality_cfg, best_page_canonical_uris, min_links_count_two_xpaths, logger
  )

  if historical_links_one_plus_one_star
    best_page_links = historical_links_one_plus_one_star
    best_star_count = "1+1"
    min_links_count_two_xpaths = best_page_links[:links].length + 1
    best_page_canonical_uris = best_page_links[:links].map(&:canonical_uri)
  end

  logger.log("Trying xpaths with 1+2 stars")
  historical_links_one_plus_two_stars = try_two_masked_xpaths(
    links_by_masked_xpath_one_star, links_by_masked_xpath_two_stars, feed_entry_canonical_uris,
    canonical_equality_cfg, best_page_canonical_uris, min_links_count_two_xpaths, logger
  )

  if historical_links_one_plus_two_stars
    best_page_links = historical_links_one_plus_two_stars
    best_star_count = "1+2"
    min_links_count_two_xpaths = best_page_links[:links].length + 1
    best_page_canonical_uris = best_page_links[:links].map(&:canonical_uri)
  end

  logger.log("Trying xpaths with 1+3 stars")
  historical_links_one_plus_three_stars = try_two_masked_xpaths(
    links_by_masked_xpath_one_star, links_by_masked_xpath_three_stars, feed_entry_canonical_uris,
    canonical_equality_cfg, best_page_canonical_uris, min_links_count_two_xpaths, logger
  )

  if historical_links_one_plus_three_stars
    best_page_links = historical_links_one_plus_three_stars
    best_star_count = "1+3"
  end

  if best_page_links
    logger.log("New best count: #{best_page_links[:links].length} with #{best_page_links[:pattern]}")
    {
      main_canonical_url: page.canonical_uri.to_s,
      main_fetch_url: page.fetch_uri.to_s,
      links: best_page_links[:links],
      pattern: best_page_links[:pattern],
      extra: "star_count: #{best_star_count}#{best_page_links[:extra]}",
      count: best_page_links[:links].length
    }
  else
    logger.log("Not an archives page or the min links count (#{min_links_count}) is not reached")
    if did_almost_match_feed
      logger.log("Almost matched feed (#{almost_match_length}/#{feed_entry_canonical_uris.length})")
      {
        main_canonical_url: page.canonical_uri.to_s,
        main_fetch_url: page.fetch_uri.to_s,
        links: feed_entry_links,
        pattern: "feed",
        extra: "almost_match: #{almost_match_length}/#{feed_entry_canonical_uris.length}",
        count: feed_entry_canonical_uris.length
      }
    else
      nil
    end
  end
end

def almost_match_length(feed_length)
  if feed_length <= 3
    feed_length
  elsif feed_length <= 7
    feed_length - 1
  elsif feed_length <= 25
    feed_length - 2
  elsif feed_length <= 62
    feed_length - 3
  else
    feed_length - 7
  end
end

def try_masked_xpath(
  page_links, feed_entry_canonical_uris, feed_entry_canonical_uris_set, canonical_equality_cfg, star_count,
  xpath_name, fewer_stars_canonical_uris, fewer_stars_have_dates, min_links_count_one_xpath,
  min_links_count_two_xpaths, logger
)
  links_by_masked_xpath = group_links_by_masked_xpath(
    page_links, feed_entry_canonical_uris_set, xpath_name, star_count
  )
  logger.log("Masked xpaths: #{links_by_masked_xpath.length}")

  # Collapse consecutive duplicates: [a, b, b, c] -> [a, b, c] but [a, b, c, b] -> [a, b, c, b]
  collapsed_links_by_masked_xpath = links_by_masked_xpath.to_h do |masked_xpath, masked_xpath_links|
    collapsed_links = []
    masked_xpath_links.length.times do |index|
      if index == 0 || masked_xpath_links[index].url != masked_xpath_links[index - 1].url
        collapsed_links << masked_xpath_links[index]
      end
    end
    [masked_xpath, collapsed_links]
  end

  # Try to extract dates
  date_relative_xpaths_by_masked_xpath = {}
  max_dates_by_masked_xpath = {}
  collapsed_links_by_masked_xpath.each do |masked_xpath, masked_xpath_links|
    masked_xpath_links_matching_feed = masked_xpath_links
      .filter { |link| feed_entry_canonical_uris_set.include?(link.canonical_uri) }
    next unless masked_xpath_links_matching_feed.length == feed_entry_canonical_uris.length
    last_star_index = masked_xpath.rindex("*")
    link_ancestors_till_star = masked_xpath[last_star_index..].count("/")
    relative_xpath_to_top_parent = "/.." * link_ancestors_till_star
    date_relative_xpaths = []
    max_date = nil
    masked_xpath_links_matching_feed.each_with_index do |link, index|
      link_top_parent = link.element
      link_ancestors_till_star.times do
        link_top_parent = link_top_parent.parent
      end
      link_top_parent_path = link_top_parent.path
      link_date_relative_xpaths = []
      link_top_parent.traverse do |element|
        next unless element.text?

        date = try_extract_date(element.content)
        next unless date

        date_relative_xpath = (relative_xpath_to_top_parent + element.path[link_top_parent_path.length..])
          .delete_prefix("/")
        link_date_relative_xpaths << date_relative_xpath

        if !max_date || date > max_date
          max_date = date
        end
      end

      if index == 0
        date_relative_xpaths = link_date_relative_xpaths
      else
        link_date_relative_xpaths_set = link_date_relative_xpaths.to_set
        date_relative_xpaths.filter! { |xpath| link_date_relative_xpaths_set.include?(xpath) }
      end
    end
    next if date_relative_xpaths.length != 1

    date_relative_xpaths_by_masked_xpath[masked_xpath] = date_relative_xpaths.first
    max_dates_by_masked_xpath[masked_xpath] = max_date
  end

  # Try to find the masked xpath that matches all feed entries and covers as many links as possible
  best_xpath = nil
  best_xpath_links = nil
  best_xpath_has_dates = nil
  did_almost_match_feed = false
  almost_match_length = nil
  collapsed_links_by_masked_xpath.each do |masked_xpath, masked_xpath_links|
    # If each entry has a date, filter links to ones with dates
    if date_relative_xpaths_by_masked_xpath.key?(masked_xpath)
      filtered_masked_xpath_links = masked_xpath_links.filter do |link|
        link_date_xpath = date_relative_xpaths_by_masked_xpath[masked_xpath]
        link_date_nodes = link
          .element
          .xpath(link_date_xpath)
          .to_a
          .filter(&:text?)
        next false if link_date_nodes.empty?
        if link_date_nodes.length > 1
          logger.log("Multiple dates found for #{link.xpath} + #{link_date_xpath}: #{link_date_nodes}")
          next false
        end
        date = try_extract_date(link_date_nodes.first.content)
        next false unless date

        date <= max_dates_by_masked_xpath[masked_xpath]
      end

      if filtered_masked_xpath_links.length != masked_xpath_links.length
        logger.log("Filtered links by dates: #{masked_xpath_links.length} -> #{filtered_masked_xpath_links.length}")
        masked_xpath_links = filtered_masked_xpath_links
      end
    else
      next if fewer_stars_have_dates
    end

    # If the set of links is almost covering feed, the feed could be complete with few random links thrown in
    masked_xpath_canonical_uris = masked_xpath_links.map(&:canonical_uri)
    if masked_xpath_links.length < feed_entry_canonical_uris.length &&
      masked_xpath_links.length >= almost_match_length(feed_entry_canonical_uris.length) &&
      masked_xpath_canonical_uris.all? { |uri| feed_entry_canonical_uris_set.include?(uri) }

      did_almost_match_feed = true
      almost_match_length = masked_xpath_links.length
    end

    next if masked_xpath_links.length < feed_entry_canonical_uris.length
    next if masked_xpath_links.length < min_links_count_one_xpath
    next if best_xpath_links && best_xpath_links.length >= masked_xpath_links.length

    masked_xpath_canonical_uris_set = masked_xpath_canonical_uris.to_canonical_uri_set(canonical_equality_cfg)
    masked_xpath_fetch_urls = masked_xpath_links.map(&:url)
    masked_xpath_fetch_urls_set = masked_xpath_fetch_urls.to_set
    next unless feed_entry_canonical_uris
      .all? { |item_uri| masked_xpath_canonical_uris_set.include?(item_uri) }

    if masked_xpath_fetch_urls_set.length != masked_xpath_fetch_urls.length
      logger.log("Masked xpath #{masked_xpath} has all links but also duplicates: #{masked_xpath_canonical_uris.map(&:to_s)}")
      next
    end

    is_matching_feed = feed_entry_canonical_uris
      .zip(masked_xpath_canonical_uris[...feed_entry_canonical_uris.length])
      .all? { |xpath_uri, entry_uri| canonical_uri_equal?(xpath_uri, entry_uri, canonical_equality_cfg) }
    is_matching_fewer_stars_links = !fewer_stars_canonical_uris ||
      fewer_stars_canonical_uris
        .zip(masked_xpath_canonical_uris[...fewer_stars_canonical_uris.length])
        .all? do |xpath_uri, fewer_stars_uri|
        canonical_uri_equal?(xpath_uri, fewer_stars_uri, canonical_equality_cfg)
      end
    if is_matching_feed && is_matching_fewer_stars_links
      best_xpath = masked_xpath
      best_xpath_links = masked_xpath_links
      best_xpath_has_dates = date_relative_xpaths_by_masked_xpath.key?(masked_xpath)
      collapsion_log_str = get_collapsion_log_str(masked_xpath, links_by_masked_xpath, collapsed_links_by_masked_xpath)
      dates_log_str = best_xpath_has_dates ? ", dates" : ''
      logger.log("Masked xpath is good: #{masked_xpath}#{collapsion_log_str} (#{masked_xpath_links.length} links#{dates_log_str})")
      next
    end

    reversed_masked_xpath_links = masked_xpath_links.reverse
    reversed_masked_xpath_canonical_uris = masked_xpath_canonical_uris.reverse
    is_reversed_matching_feed = feed_entry_canonical_uris
      .zip(reversed_masked_xpath_canonical_uris[...feed_entry_canonical_uris.length])
      .all? { |xpath_uri, entry_uri| canonical_uri_equal?(xpath_uri, entry_uri, canonical_equality_cfg) }
    is_reversed_matching_fewer_stars_links = !fewer_stars_canonical_uris ||
      fewer_stars_canonical_uris
        .zip(reversed_masked_xpath_canonical_uris[...fewer_stars_canonical_uris.length])
        .all? do |xpath_uri, fewer_stars_uri|
        canonical_uri_equal?(xpath_uri, fewer_stars_uri, canonical_equality_cfg)
      end
    if is_reversed_matching_feed && is_reversed_matching_fewer_stars_links
      best_xpath = masked_xpath
      best_xpath_links = reversed_masked_xpath_links
      best_xpath_has_dates = date_relative_xpaths_by_masked_xpath.key?(masked_xpath)
      collapsion_log_str = get_collapsion_log_str(masked_xpath, links_by_masked_xpath, collapsed_links_by_masked_xpath)
      dates_log_str = best_xpath_has_dates ? ", dates" : ''
      logger.log("Masked xpath is good in reverse order: #{masked_xpath}#{collapsion_log_str} (#{reversed_masked_xpath_links.length} links#{dates_log_str})")
      next
    end

    logger.log("Masked xpath #{masked_xpath} has all links")
    logger.log("#{feed_entry_canonical_uris.map(&:to_s)}")
    logger.log("but not in the right order:")
    logger.log("#{masked_xpath_canonical_uris.map(&:to_s)}")
    if fewer_stars_canonical_uris
      logger.log("or not matching fewer stars links:")
      logger.log("#{fewer_stars_canonical_uris.map(&:to_s)}")
    end
  end

  if best_xpath_links
    return {
      is_full_match: true,
      pattern: "archives",
      links: best_xpath_links,
      has_dates: best_xpath_has_dates,
      extra: "<br>xpath: #{best_xpath}",
      links_by_masked_xpath: collapsed_links_by_masked_xpath
    }
  end

  if feed_entry_canonical_uris.length < 3
    return {
      is_full_match: false,
      did_almost_match_feed: did_almost_match_feed,
      almost_match_length: almost_match_length,
      links_by_masked_xpath: collapsed_links_by_masked_xpath
    }
  end

  # Try to see if the first post doesn't match due to being decorated somehow but other strictly fit
  # Don't do dates matching or fuzzy matching or reverse matching
  first_link = page_links.find do |page_link|
    canonical_uri_equal?(page_link.canonical_uri, feed_entry_canonical_uris.first, canonical_equality_cfg)
  end
  if first_link
    best_xpath_without_first = nil
    best_xpath_links_without_first = nil
    collapsed_links_by_masked_xpath.each do |masked_xpath, masked_xpath_links|
      next if masked_xpath_links.length < feed_entry_canonical_uris.length - 1
      next if masked_xpath_links.length < min_links_count_two_xpaths - 1
      next if best_xpath_links && best_xpath_links.length >= masked_xpath_links.length + 1
      next if best_xpath_links_without_first &&
        best_xpath_links_without_first.length >= masked_xpath_links.length

      masked_xpath_canonical_uris = masked_xpath_links.map(&:canonical_uri)
      is_matching_feed = feed_entry_canonical_uris[1..]
        .zip(masked_xpath_canonical_uris[...feed_entry_canonical_uris.length - 1])
        .all? { |xpath_uri, entry_uri| canonical_uri_equal?(xpath_uri, entry_uri, canonical_equality_cfg) }
      is_matching_fewer_stars_links = !fewer_stars_canonical_uris ||
        fewer_stars_canonical_uris[1..]
          .zip(masked_xpath_canonical_uris[...fewer_stars_canonical_uris.length - 1])
          .all? do |xpath_uri, fewer_stars_uri|
          canonical_uri_equal?(xpath_uri, fewer_stars_uri, canonical_equality_cfg)
        end
      if is_matching_feed && is_matching_fewer_stars_links
        collapsion_log_str = get_collapsion_log_str(
          masked_xpath, links_by_masked_xpath, collapsed_links_by_masked_xpath
        )
        logger.log("Masked xpath is good: #{masked_xpath}#{collapsion_log_str} (1 + #{masked_xpath_links.length} links)")
        best_xpath_without_first = masked_xpath
        best_xpath_links_without_first = masked_xpath_links
        next
      end
    end

    if best_xpath_links_without_first
      return {
        is_full_match: true,
        pattern: "archives_2xpaths",
        links: [first_link] + best_xpath_links_without_first,
        extra: "<br>counts: 1 + #{best_xpath_links_without_first.length}<br>prefix_xpath: #{first_link.xpath}<br>suffix_xpath: #{best_xpath_without_first}",
        links_by_masked_xpath: collapsed_links_by_masked_xpath
      }
    end
  end

  {
    is_full_match: false,
    did_almost_match_feed: did_almost_match_feed,
    almost_match_length: almost_match_length,
    links_by_masked_xpath: collapsed_links_by_masked_xpath
  }
end

def try_two_masked_xpaths(
  prefix_links_by_masked_xpath, suffix_links_by_masked_xpath, feed_entry_canonical_uris,
  canonical_equality_cfg, prev_archives_canonical_uris, min_links_count, logger
)
  feed_prefix_xpaths_by_length = {}
  prefix_links_by_masked_xpath.each do |masked_xpath, masked_xpath_links|
    next if masked_xpath_links.length >= feed_entry_canonical_uris.length

    feed_entry_canonical_uris.zip(masked_xpath_links).each_with_index do |pair, index|
      feed_entry_canonical_uri, masked_xpath_link = pair
      if index > 0 && masked_xpath_link.nil?
        prefix_length = index
        unless feed_prefix_xpaths_by_length.key?(prefix_length)
          feed_prefix_xpaths_by_length[prefix_length] = []
        end
        feed_prefix_xpaths_by_length[prefix_length] << masked_xpath
        break
      elsif !canonical_uri_equal?(
        feed_entry_canonical_uri, masked_xpath_link.canonical_uri, canonical_equality_cfg
      )
        break # Not a prefix
      end
    end
  end

  suffix_links_by_masked_xpath.each do |masked_suffix_xpath, masked_suffix_xpath_links|
    feed_suffix_start_index = feed_entry_canonical_uris.index do |entry_uri|
      canonical_uri_equal?(entry_uri, masked_suffix_xpath_links[0].canonical_uri, canonical_equality_cfg)
    end
    next unless feed_suffix_start_index

    is_suffix = true
    feed_entry_canonical_uris[feed_suffix_start_index..]
      .zip(masked_suffix_xpath_links)
      .each do |feed_entry_canonical_uri, masked_xpath_link|

      if feed_entry_canonical_uri.nil?
        break # suffix found
      elsif masked_xpath_link.nil?
        is_suffix = false
        break
      elsif !canonical_uri_equal?(
        feed_entry_canonical_uri, masked_xpath_link.canonical_uri, canonical_equality_cfg
      )
        is_suffix = false
        break
      end
    end
    next unless is_suffix

    target_prefix_length = feed_suffix_start_index
    next unless feed_prefix_xpaths_by_length.key?(target_prefix_length)
    total_length = target_prefix_length + masked_suffix_xpath_links.length
    next unless total_length >= min_links_count

    masked_prefix_xpath = feed_prefix_xpaths_by_length[target_prefix_length][0]
    masked_prefix_xpath_links = prefix_links_by_masked_xpath[masked_prefix_xpath]

    # Ensure the first suffix link appears on the page after the last prefix link
    # Find the lowest common parent and see if prefix parent comes before suffix parent
    last_prefix_link = masked_prefix_xpath_links.last
    first_suffix_link = masked_suffix_xpath_links.first
    # Link can't be a parent of another link. Not actually expecting that but just in case
    next if last_prefix_link.element == first_suffix_link.element.parent ||
      first_suffix_link.element == last_prefix_link.element.parent
    prefix_parent_id_to_self_and_child = {}
    current_prefix_element = last_prefix_link.element
    while current_prefix_element.element? do
      prefix_parent_id_to_self_and_child[current_prefix_element.parent.pointer_id] =
        [current_prefix_element.parent, current_prefix_element]
      current_prefix_element = current_prefix_element.parent
    end
    top_suffix_element = first_suffix_link.element
    while top_suffix_element.element? &&
      !prefix_parent_id_to_self_and_child.key?(top_suffix_element.parent.pointer_id) do

      top_suffix_element = top_suffix_element.parent
    end
    common_parent, top_prefix_element =
      prefix_parent_id_to_self_and_child[top_suffix_element.parent.pointer_id]
    is_last_prefix_before_first_suffix = nil
    common_parent.children.each do |child|
      if child == top_prefix_element
        is_last_prefix_before_first_suffix = true
        break
      end
      if child == top_suffix_element
        is_last_prefix_before_first_suffix = false
        break
      end
    end
    next unless is_last_prefix_before_first_suffix

    logger.log("Found partition with two xpaths: #{target_prefix_length} + #{masked_suffix_xpath_links.length}")
    # Skipping collapsion log because it is minor and happened in a different func
    logger.log("Prefix xpath: #{masked_prefix_xpath}")
    logger.log("Suffix xpath: #{masked_suffix_xpath}")

    combined_links = masked_prefix_xpath_links + masked_suffix_xpath_links
    combined_canonical_uris = combined_links.map(&:canonical_uri)
    combined_canonical_uris_set = combined_canonical_uris.to_canonical_uri_set(canonical_equality_cfg)
    if combined_canonical_uris.length != combined_canonical_uris_set.length
      logger.log("Combination has all feed links but also duplicates: #{combined_canonical_uris.map(&:to_s)}")
      next
    end

    is_matching_prev_archives_links = !prev_archives_canonical_uris ||
      prev_archives_canonical_uris
        .zip(combined_canonical_uris[...prev_archives_canonical_uris.length])
        .all? do |xpath_uri, fewer_stars_uri|
        canonical_uri_equal?(xpath_uri, fewer_stars_uri, canonical_equality_cfg)
      end
    unless is_matching_prev_archives_links
      logger.log("Combination doesn't match previous archives links")
      next
    end

    logger.log("Combination is good")
    return {
      pattern: "archives_2xpaths",
      links: combined_links,
      extra: "<br>counts: #{target_prefix_length} + #{masked_suffix_xpath_links.length}<br>prefix_xpath: #{masked_prefix_xpath}<br>suffix_xpath: #{masked_suffix_xpath}"
    }
  end

  nil
end

def try_extract_date(text)
  text = text.strip
  return nil if text.empty?

  # Assuming dates can't get longer than that
  # Longest seen was "(September 12 2005, last updated September 17 2005)"
  # at https://tratt.net/laurie/blog/archive.html
  return nil if text.length > 60

  return nil if text.include?("/") # Can't distinguish between MM/DD/YY and DD/MM/YY
  return nil unless text.match?(/\d/) # Dates must have numbers

  begin
    date_hash = Date._parse(text)
    return nil unless date_hash && date_hash.key?(:year) && date_hash.key?(:mon) && date_hash.key?(:mday)

    text_numbers = text.scan(/\d+/)
    year_string = date_hash[:year].to_s
    day_string = date_hash[:mday].to_s
    day_string_padded = day_string.rjust(2, '0')
    return nil unless text_numbers.any? { |number| [year_string, year_string[-2..]].include?(number) }
    return nil unless text_numbers.any? { |number| [day_string, day_string_padded].include?(number) }

    date = Date.new(date_hash[:year], date_hash[:mon], date_hash[:mday])
    return date
  rescue
    return nil
  end
end