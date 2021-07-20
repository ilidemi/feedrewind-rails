require_relative 'historical_common'

def try_extract_archives(
  page, page_links, page_canonical_uris_set, feed_entry_links, feed_entry_canonical_uris,
  feed_entry_canonical_uris_set, canonical_equality_cfg, min_links_count, logger
)
  return nil unless feed_entry_canonical_uris.all? { |item_uri| page_canonical_uris_set.include?(item_uri) }

  logger.log("Possible archives page: #{page.canonical_uri}")
  min_links_count_one_xpath = min_links_count_two_xpaths = min_links_count
  best_page_links = nil
  fewer_stars_canonical_uris = nil
  best_star_count = nil
  did_almost_match_feed = false
  almost_match_length = nil

  logger.log("Trying xpaths with a single star")
  historical_links_single_star = try_masked_xpaths(
    page_links, feed_entry_canonical_uris, feed_entry_canonical_uris_set, canonical_equality_cfg,
    :get_single_masked_xpaths, :xpath, fewer_stars_canonical_uris,
    min_links_count_one_xpath, min_links_count_two_xpaths, logger
  )

  if historical_links_single_star[:is_full_match]
    best_page_links = historical_links_single_star
    best_star_count = 1
    if historical_links_single_star[:is_one_xpath]
      min_links_count_one_xpath = best_page_links[:links].length + 1
    else
      min_links_count_one_xpath = best_page_links[:links].length
    end
    min_links_count_two_xpaths = best_page_links[:links].length + 1
    fewer_stars_canonical_uris = best_page_links[:links].map(&:canonical_uri)
  else
    did_almost_match_feed ||= historical_links_single_star[:did_almost_match_feed]
    unless almost_match_length && almost_match_length > historical_links_single_star[:almost_match_length]
      almost_match_length = historical_links_single_star[:almost_match_length]
    end
  end

  logger.log("Trying xpaths with two stars")
  historical_links_double_star = try_masked_xpaths(
    page_links, feed_entry_canonical_uris, feed_entry_canonical_uris_set, canonical_equality_cfg,
    :get_double_masked_xpaths, :class_xpath, fewer_stars_canonical_uris,
    min_links_count_one_xpath, min_links_count_two_xpaths, logger
  )

  if historical_links_double_star[:is_full_match]
    best_page_links = historical_links_double_star
    best_star_count = 2
    if historical_links_double_star[:is_one_xpath]
      min_links_count_one_xpath = best_page_links[:links].length + 1
    else
      min_links_count_one_xpath = best_page_links[:links].length
    end
    min_links_count_two_xpaths = best_page_links[:links].length + 1
    fewer_stars_canonical_uris = best_page_links[:links].map(&:canonical_uri)
  else
    did_almost_match_feed ||= historical_links_double_star[:did_almost_match_feed]
    unless almost_match_length && almost_match_length > historical_links_double_star[:almost_match_length]
      almost_match_length = historical_links_double_star[:almost_match_length]
    end
  end

  logger.log("Trying xpaths with three stars")
  historical_links_triple_star = try_masked_xpaths(
    page_links, feed_entry_canonical_uris, feed_entry_canonical_uris_set, canonical_equality_cfg,
    :get_triple_masked_xpaths, :class_xpath, fewer_stars_canonical_uris,
    min_links_count_one_xpath, min_links_count_two_xpaths, logger
  )

  if historical_links_triple_star[:is_full_match]
    best_page_links = historical_links_triple_star
    best_star_count = 3
  else
    did_almost_match_feed ||= historical_links_triple_star[:did_almost_match_feed]
    unless almost_match_length && almost_match_length > historical_links_triple_star[:almost_match_length]
      almost_match_length = historical_links_triple_star[:almost_match_length]
    end
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

def try_masked_xpaths(
  page_links, feed_entry_canonical_uris, feed_entry_canonical_uris_set, canonical_equality_cfg,
  get_masked_xpaths_name, xpath_name, fewer_stars_canonical_uris, min_links_count_one_xpath,
  min_links_count_two_xpaths, logger
)
  get_masked_xpaths_func = method(get_masked_xpaths_name)
  links_by_masked_xpath = group_links_by_masked_xpath(
    page_links, feed_entry_canonical_uris_set, xpath_name, get_masked_xpaths_func
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

  # Try to find the masked xpath that matches all feed entries and covers as many links as possible
  best_xpath = nil
  best_xpath_links = nil
  did_almost_match_feed = false
  almost_match_length = nil
  collapsed_links_by_masked_xpath.each do |masked_xpath, masked_xpath_links|
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
    next unless feed_entry_canonical_uris.all? { |item_uri| masked_xpath_canonical_uris_set.include?(item_uri) }

    if masked_xpath_fetch_urls_set.length != masked_xpath_fetch_urls.length
      logger.log("Masked xpath #{masked_xpath} has all links but also duplicates: #{masked_xpath_canonical_uris}")
      next
    end

    is_matching_feed = feed_entry_canonical_uris
      .zip(masked_xpath_canonical_uris[0...feed_entry_canonical_uris.length])
      .all? { |xpath_uri, entry_uri| canonical_uri_equal?(xpath_uri, entry_uri, canonical_equality_cfg) }
    is_matching_fewer_stars_links = !fewer_stars_canonical_uris ||
      fewer_stars_canonical_uris
        .zip(masked_xpath_canonical_uris[0...fewer_stars_canonical_uris.length])
        .all? do |xpath_uri, fewer_stars_uri|
        canonical_uri_equal?(xpath_uri, fewer_stars_uri, canonical_equality_cfg)
      end
    if is_matching_feed && is_matching_fewer_stars_links
      collapsion_log_str = get_collapsion_log_str(masked_xpath, links_by_masked_xpath, collapsed_links_by_masked_xpath)
      logger.log("Masked xpath is good: #{masked_xpath}#{collapsion_log_str} (#{masked_xpath_links.length} links)")
      best_xpath = masked_xpath
      best_xpath_links = masked_xpath_links
      next
    end

    reversed_masked_xpath_links = masked_xpath_links.reverse
    reversed_masked_xpath_canonical_uris = masked_xpath_canonical_uris.reverse
    is_reversed_matching_feed = feed_entry_canonical_uris
      .zip(reversed_masked_xpath_canonical_uris[0...feed_entry_canonical_uris.length])
      .all? { |xpath_uri, entry_uri| canonical_uri_equal?(xpath_uri, entry_uri, canonical_equality_cfg) }
    is_reversed_matching_fewer_stars_links = !fewer_stars_canonical_uris ||
      fewer_stars_canonical_uris
        .zip(reversed_masked_xpath_canonical_uris[0...fewer_stars_canonical_uris.length])
        .all? do |xpath_uri, fewer_stars_uri|
        canonical_uri_equal?(xpath_uri, fewer_stars_uri, canonical_equality_cfg)
      end
    if is_reversed_matching_feed && is_reversed_matching_fewer_stars_links
      collapsion_log_str = get_collapsion_log_str(masked_xpath, links_by_masked_xpath, collapsed_links_by_masked_xpath)
      logger.log("Masked xpath is good in reverse order: #{masked_xpath}#{collapsion_log_str} (#{reversed_masked_xpath_links.length} links)")
      best_xpath = masked_xpath
      best_xpath_links = reversed_masked_xpath_links
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
      is_one_xpath: true,
      extra: "<br>xpath: #{best_xpath}"
    }
  end

  if feed_entry_canonical_uris.length < 3
    return {
      is_full_match: false,
      did_almost_match_feed: did_almost_match_feed,
      almost_match_length: almost_match_length
    }
  end

  # Try to combine archives from two masked xpaths covering a prefix and a suffix of feed entries
  feed_prefix_xpaths_by_length = {}
  collapsed_links_by_masked_xpath.each do |masked_xpath, masked_xpath_links|
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

  collapsed_links_by_masked_xpath.each do |masked_suffix_xpath, masked_suffix_xpath_links|
    feed_suffix_start_index = feed_entry_canonical_uris.index do |entry_uri|
      canonical_uri_equal?(entry_uri, masked_suffix_xpath_links[0].canonical_uri, canonical_equality_cfg)
    end
    next unless feed_suffix_start_index

    is_suffix = true
    feed_entry_canonical_uris[feed_suffix_start_index..-1]
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
    next unless total_length >= min_links_count_two_xpaths

    masked_prefix_xpath = feed_prefix_xpaths_by_length[target_prefix_length][0]
    masked_prefix_xpath_links = collapsed_links_by_masked_xpath[masked_prefix_xpath]

    # Ensure the first suffix link appears on the page after the last prefix link
    # Find the lowest common parent and see if prefix parent comes before suffix parent
    last_prefix_link = masked_prefix_xpath_links.last
    first_suffix_link = masked_suffix_xpath_links.first
    # Link can't be a parent of another link. Not actually expecting that but just in case
    next if last_prefix_link.element.pointer_id == first_suffix_link.element.parent.pointer_id ||
      first_suffix_link.element.pointer_id == last_prefix_link.element.parent.pointer_id
    prefix_parent_id_to_self_and_child = {}
    current_prefix_element = last_prefix_link.element
    while current_prefix_element.is_a?(Nokogiri::XML::Element) do
      prefix_parent_id_to_self_and_child[current_prefix_element.parent.pointer_id] =
        [current_prefix_element.parent, current_prefix_element]
      current_prefix_element = current_prefix_element.parent
    end
    top_suffix_element = first_suffix_link.element
    while top_suffix_element.is_a?(Nokogiri::XML::Element) &&
      !prefix_parent_id_to_self_and_child.key?(top_suffix_element.parent.pointer_id) do

      top_suffix_element = top_suffix_element.parent
    end
    common_parent, top_prefix_element =
      prefix_parent_id_to_self_and_child[top_suffix_element.parent.pointer_id]
    top_prefix_element_id = top_prefix_element.pointer_id
    top_suffix_element_id = top_suffix_element.pointer_id
    is_last_prefix_before_first_suffix = nil
    common_parent.children.each do |child|
      if child.pointer_id == top_prefix_element_id
        is_last_prefix_before_first_suffix = true
        break
      end
      if child.pointer_id == top_suffix_element_id
        is_last_prefix_before_first_suffix = false
        break
      end
    end
    next unless is_last_prefix_before_first_suffix

    logger.log("Found partition with two xpaths: #{target_prefix_length} + #{masked_suffix_xpath_links.length}")
    prefix_collapsion_log_str = get_collapsion_log_str(
      masked_prefix_xpath, links_by_masked_xpath, collapsed_links_by_masked_xpath
    )
    logger.log("Prefix xpath: #{masked_prefix_xpath}#{prefix_collapsion_log_str}")
    suffix_collapsion_log_str = get_collapsion_log_str(
      masked_suffix_xpath, links_by_masked_xpath, collapsed_links_by_masked_xpath
    )
    logger.log("Suffix xpath: #{masked_suffix_xpath}#{suffix_collapsion_log_str}")

    combined_links = masked_prefix_xpath_links + masked_suffix_xpath_links
    combined_canonical_uris = combined_links.map(&:canonical_uri)
    combined_canonical_uris_set = combined_canonical_uris.to_canonical_uri_set(canonical_equality_cfg)
    if combined_canonical_uris.length != combined_canonical_uris_set.length
      logger.log("Combination has all feed links but also duplicates: #{combined_canonical_uris}")
      next
    end

    is_matching_fewer_stars_links = !fewer_stars_canonical_uris ||
      fewer_stars_canonical_uris
        .zip(combined_canonical_uris[0...fewer_stars_canonical_uris.length])
        .all? do |xpath_uri, fewer_stars_uri|
        canonical_uri_equal?(xpath_uri, fewer_stars_uri, canonical_equality_cfg)
      end
    unless is_matching_fewer_stars_links
      logger.log("Combination doesn't match fewer stars links")
      next
    end

    logger.log("Combination is good")
    return {
      is_full_match: true,
      pattern: "archives_2xpaths",
      links: combined_links,
      is_one_xpath: false,
      extra: "<br>counts: #{target_prefix_length} + #{masked_suffix_xpath_links.length}<br>prefix_xpath: #{masked_prefix_xpath}<br>suffix_xpath: #{masked_suffix_xpath}"
    }
  end

  {
    is_full_match: false,
    did_almost_match_feed: did_almost_match_feed,
    almost_match_length: almost_match_length
  }
end

def almost_match_length(feed_length)
  if feed_length <= 3
    feed_length
  elsif feed_length <= 7
    feed_length - 1
  elsif feed_length <= 25
    feed_length - 2
  else
    feed_length - 3
  end
end

def get_triple_masked_xpaths(xpath)
  matches = xpath.to_enum(:scan, /\[\d+\]/).map { Regexp.last_match }
  matches.combination(3).map do |match1, match2, match3|
    start1, finish1 = match1.offset(0)
    start2, finish2 = match2.offset(0)
    start3, finish3 = match3.offset(0)
    xpath[0..start1] + '*' +
      xpath[(finish1 - 1)..start2] + '*' +
      xpath[(finish2 - 1)..start3] + '*' +
      xpath[(finish3 - 1)..-1]
  end
end
