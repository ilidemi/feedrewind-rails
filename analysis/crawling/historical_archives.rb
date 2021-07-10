require_relative 'historical_common'

def try_extract_archives(
  page, page_links, page_canonical_uris_set, feed_entry_canonical_uris, feed_entry_canonical_uris_set,
  canonical_equality_cfg, best_result_subpattern_priority, min_links_count, logger
)
  return nil unless feed_entry_canonical_uris.all? { |item_uri| page_canonical_uris_set.include?(item_uri) }

  logger.log("Possible archives page: #{page.canonical_uri}")
  best_result = nil
  best_result_star_count = nil
  best_page_links = nil
  if best_result_subpattern_priority.nil? || best_result_subpattern_priority > SUBPATTERN_PRIORITIES[:archives_1star]
    min_page_links_count = min_links_count
  else
    min_page_links_count = min_links_count + 1
  end

  logger.log("Trying xpaths with a single star")
  historical_links_single_star = try_masked_xpaths(
    page_links, feed_entry_canonical_uris, feed_entry_canonical_uris_set, canonical_equality_cfg,
    :get_single_masked_xpaths, :xpath, min_page_links_count, logger
  )

  if historical_links_single_star
    best_page_links = historical_links_single_star
    best_result_subpattern_priority = SUBPATTERN_PRIORITIES[:archives_1star]
    best_result_star_count = 1
    min_links_count = best_page_links[:links].length
  end

  if best_result_subpattern_priority.nil? || best_result_subpattern_priority > SUBPATTERN_PRIORITIES[:archives_2star]
    min_page_links_count = min_links_count
  elsif best_result_subpattern_priority == SUBPATTERN_PRIORITIES[:archives_2star]
    min_page_links_count = min_links_count + 1
  else
    min_page_links_count = (min_links_count * 1.5).ceil
  end

  logger.log("Trying xpaths with two stars")
  historical_links_double_star = try_masked_xpaths(
    page_links, feed_entry_canonical_uris, feed_entry_canonical_uris_set, canonical_equality_cfg,
    :get_double_masked_xpaths, :class_xpath, min_page_links_count, logger
  )

  if historical_links_double_star
    best_page_links = historical_links_double_star
    best_result_subpattern_priority = SUBPATTERN_PRIORITIES[:archives_2star]
    best_result_star_count = 2
    min_links_count = best_page_links[:links].length
  end

  if best_result_subpattern_priority.nil? || best_result_subpattern_priority > SUBPATTERN_PRIORITIES[:archives_3star]
    min_page_links_count = min_links_count
  elsif best_result_subpattern_priority == SUBPATTERN_PRIORITIES[:archives_3star]
    min_page_links_count = min_links_count + 1
  else
    min_page_links_count = (min_links_count * 1.5).ceil
  end

  logger.log("Trying xpaths with three stars")
  historical_links_triple_star = try_masked_xpaths(
    page_links, feed_entry_canonical_uris, feed_entry_canonical_uris_set, canonical_equality_cfg,
    :get_triple_masked_xpaths,:class_xpath, min_page_links_count, logger
  )

  if historical_links_triple_star
    best_page_links = historical_links_triple_star
    best_result_subpattern_priority = SUBPATTERN_PRIORITIES[:archives_3star]
    best_result_star_count = 3
    min_links_count = best_page_links[:links].length
  end

  if best_page_links
    best_result = {
      main_canonical_url: page.canonical_uri.to_s,
      main_fetch_url: page.fetch_uri.to_s,
      links: best_page_links[:links],
      pattern: best_page_links[:pattern],
      extra: "star_count: #{best_result_star_count}#{best_page_links[:extra]}"
    }
  else
    logger.log("Not an archives page or the min links count (#{min_links_count}) is not reached")
  end

  if best_result
    logger.log("New best count: #{min_links_count} with #{best_result[:pattern]}")
    { best_result: best_result, subpattern_priority: best_result_subpattern_priority, count: min_links_count }
  else
    nil
  end
end

def try_masked_xpaths(
  page_links, feed_entry_canonical_uris, feed_entry_canonical_uris_set, canonical_equality_cfg,
  get_masked_xpaths_name, xpath_name, min_links_count, logger
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

  best_xpath_links = nil
  collapsed_links_by_masked_xpath.each do |masked_xpath, masked_xpath_links|
    next if masked_xpath_links.length < feed_entry_canonical_uris.length
    next if masked_xpath_links.length < min_links_count
    next if best_xpath_links && best_xpath_links.length >= masked_xpath_links.length

    masked_xpath_canonical_uris = masked_xpath_links.map(&:canonical_uri)
    masked_xpath_fetch_urls = masked_xpath_links.map(&:url)
    masked_xpath_canonical_uris_set = masked_xpath_canonical_uris.to_canonical_uri_set(canonical_equality_cfg)
    masked_xpath_fetch_urls_set = masked_xpath_fetch_urls.to_set
    next unless feed_entry_canonical_uris.all? { |item_uri| masked_xpath_canonical_uris_set.include?(item_uri) }

    if masked_xpath_fetch_urls_set.length != masked_xpath_fetch_urls.length
      logger.log("Masked xpath #{masked_xpath} has all links but also duplicates: #{masked_xpath_canonical_uris}")
      next
    end

    is_masked_xpath_matching_feed = feed_entry_canonical_uris
      .zip(masked_xpath_canonical_uris[0...feed_entry_canonical_uris.length])
      .all? { |xpath_uri, entry_uri| canonical_uri_equal?(xpath_uri, entry_uri, canonical_equality_cfg) }
    if is_masked_xpath_matching_feed
      collapsion_log_str = get_collapsion_log_str(masked_xpath, links_by_masked_xpath, collapsed_links_by_masked_xpath)
      logger.log("Masked xpath is good: #{masked_xpath}#{collapsion_log_str} (#{masked_xpath_links.length} links)")
      best_xpath_links = masked_xpath_links
      next
    end

    reversed_masked_xpath_links = masked_xpath_links.reverse
    reversed_masked_xpath_canonical_uris = masked_xpath_canonical_uris.reverse
    is_reversed_masked_xpath_matching_feed = feed_entry_canonical_uris
      .zip(reversed_masked_xpath_canonical_uris[0...feed_entry_canonical_uris.length])
      .all? { |xpath_uri, entry_uri| canonical_uri_equal?(xpath_uri, entry_uri, canonical_equality_cfg) }
    if is_reversed_masked_xpath_matching_feed
      collapsion_log_str = get_collapsion_log_str(masked_xpath, links_by_masked_xpath, collapsed_links_by_masked_xpath)
      logger.log("Masked xpath is good in reverse order: #{masked_xpath}#{collapsion_log_str} (#{reversed_masked_xpath_links.length} links)")
      best_xpath_links = reversed_masked_xpath_links
      next
    end

    logger.log("Masked xpath #{masked_xpath} has all links")
    logger.log("#{feed_entry_canonical_uris}")
    logger.log("but not in the right order:")
    logger.log("#{masked_xpath_canonical_uris}")
  end

  if best_xpath_links
    return { pattern: "archives", links: best_xpath_links }
  end

  if feed_entry_canonical_uris.length < 3
    return nil
  end

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
      elsif !canonical_uri_equal?(feed_entry_canonical_uri, masked_xpath_link.canonical_uri, canonical_equality_cfg)
        break # Not a prefix
      end
    end
  end

  collapsed_links_by_masked_xpath.each do |masked_xpath, masked_xpath_links|
    feed_suffix_start_index = feed_entry_canonical_uris.index do |entry_uri|
      canonical_uri_equal?(entry_uri, masked_xpath_links[0].canonical_uri, canonical_equality_cfg)
    end
    next if feed_suffix_start_index.nil?

    is_suffix = true
    feed_entry_canonical_uris[feed_suffix_start_index..-1]
      .zip(masked_xpath_links)
      .each do |feed_entry_canonical_uri, masked_xpath_link|

      if feed_entry_canonical_uri.nil?
        break # suffix found
      elsif masked_xpath_link.nil?
        is_suffix = false
        break
      elsif !canonical_uri_equal?(feed_entry_canonical_uri, masked_xpath_link.canonical_uri, canonical_equality_cfg)
        is_suffix = false
        break
      end
    end
    next unless is_suffix

    target_prefix_length = feed_suffix_start_index
    next unless feed_prefix_xpaths_by_length.key?(target_prefix_length)
    total_length = target_prefix_length + masked_xpath_links.length
    next unless total_length > min_links_count

    masked_prefix_xpath = feed_prefix_xpaths_by_length[target_prefix_length][0]
    logger.log("Found partition with two xpaths: #{target_prefix_length} + #{masked_xpath_links.length}")
    prefix_collapsion_log_str = get_collapsion_log_str(masked_prefix_xpath, links_by_masked_xpath, collapsed_links_by_masked_xpath)
    logger.log("Prefix xpath: #{masked_prefix_xpath}#{prefix_collapsion_log_str}")
    suffix_collapsion_log_str = get_collapsion_log_str(masked_xpath, links_by_masked_xpath, collapsed_links_by_masked_xpath)
    logger.log("Suffix xpath: #{masked_xpath}#{suffix_collapsion_log_str}")

    combined_links = collapsed_links_by_masked_xpath[masked_prefix_xpath] + masked_xpath_links
    combined_canonical_uris = combined_links.map(&:canonical_uri)
    combined_canonical_uris_set = combined_canonical_uris.to_canonical_uri_set(canonical_equality_cfg)
    if combined_canonical_uris.length != combined_canonical_uris_set.length
      logger.log("Combination has all feed links but also duplicates: #{combined_canonical_uris}")
      next
    end

    logger.log("Combination is good")
    return {
      pattern: "archives_2xpaths",
      links: combined_links,
      extra: "<br>counts: #{target_prefix_length} + #{masked_xpath_links.length}<br>prefix_xpath: #{masked_prefix_xpath}<br>suffix_xpath: #{masked_xpath}"
    }
  end

  nil
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
