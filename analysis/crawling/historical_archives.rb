require_relative 'historical_common'

def try_extract_archives(
  page, page_links, page_urls_set, feed_item_urls, feed_item_urls_set, best_result_subpattern_priority,
  min_links_count, subpattern_priorities, logger
)
  return nil unless feed_item_urls.all? { |item_url| page_urls_set.include?(item_url) }

  logger.log("Possible archives page: #{page.canonical_url}")
  best_result = nil
  best_result_star_count = nil
  best_page_links = nil
  if best_result_subpattern_priority.nil? || best_result_subpattern_priority > subpattern_priorities[:archives_1star]
    min_page_links_count = min_links_count
  else
    min_page_links_count = min_links_count + 1
  end

  logger.log("Trying xpaths with a single star")
  historical_links_single_star = try_masked_xpaths(
    page_links, feed_item_urls, feed_item_urls_set, :get_single_masked_xpaths,
    :xpath, min_page_links_count, logger
  )

  if historical_links_single_star
    best_page_links = historical_links_single_star
    best_result_subpattern_priority = subpattern_priorities[:archives_1star]
    best_result_star_count = 1
    min_links_count = best_page_links[:links].length
  end

  if best_result_subpattern_priority.nil? || best_result_subpattern_priority > subpattern_priorities[:archives_2star]
    min_page_links_count = min_links_count
  elsif best_result_subpattern_priority == subpattern_priorities[:archives_2star]
    min_page_links_count = min_links_count + 1
  else
    min_page_links_count = (min_links_count * 1.5).ceil
  end

  logger.log("Trying xpaths with two stars")
  historical_links_double_star = try_masked_xpaths(
    page_links, feed_item_urls, feed_item_urls_set, :get_double_masked_xpaths,
    :class_xpath, min_page_links_count, logger
  )

  if historical_links_double_star
    best_page_links = historical_links_double_star
    best_result_subpattern_priority = subpattern_priorities[:archives_2star]
    best_result_star_count = 2
    min_links_count = best_page_links[:links].length
  end

  if best_result_subpattern_priority.nil? || best_result_subpattern_priority > subpattern_priorities[:archives_3star]
    min_page_links_count = min_links_count
  elsif best_result_subpattern_priority == subpattern_priorities[:archives_3star]
    min_page_links_count = min_links_count + 1
  else
    min_page_links_count = (min_links_count * 1.5).ceil
  end

  logger.log("Trying xpaths with three stars")
  historical_links_triple_star = try_masked_xpaths(
    page_links, feed_item_urls, feed_item_urls_set, :get_triple_masked_xpaths,
    :class_xpath, min_page_links_count, logger
  )

  if historical_links_triple_star
    best_page_links = historical_links_triple_star
    best_result_subpattern_priority = subpattern_priorities[:archives_3star]
    best_result_star_count = 3
    min_links_count = best_page_links[:links].length
  end

  if best_page_links
    best_result = {
      main_canonical_url: page.canonical_url,
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
  page_links, feed_item_urls, feed_item_urls_set, get_masked_xpaths_name, xpath_name, min_links_count, logger
)
  get_masked_xpaths_func = method(get_masked_xpaths_name)
  links_by_masked_xpath = group_links_by_masked_xpath(
    page_links, feed_item_urls_set, xpath_name, get_masked_xpaths_func
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
    next if masked_xpath_links.length < feed_item_urls.length
    next if masked_xpath_links.length < min_links_count
    next if best_xpath_links && best_xpath_links.length >= masked_xpath_links.length

    masked_xpath_link_canonical_urls = masked_xpath_links.map(&:canonical_url)
    masked_xpath_link_fetch_urls = masked_xpath_links.map(&:url)
    masked_xpath_link_canonical_urls_set = masked_xpath_link_canonical_urls.to_set
    masked_xpath_link_fetch_urls_set = masked_xpath_link_fetch_urls.to_set
    next unless feed_item_urls.all? { |item_url| masked_xpath_link_canonical_urls_set.include?(item_url) }

    if masked_xpath_link_fetch_urls_set.length != masked_xpath_link_fetch_urls.length
      logger.log("Masked xpath #{masked_xpath} has all links but also duplicates: #{masked_xpath_link_canonical_urls}")
      next
    end

    if feed_item_urls == masked_xpath_link_canonical_urls[0...feed_item_urls.length]
      collapsion_log_str = get_collapsion_log_str(masked_xpath, links_by_masked_xpath, collapsed_links_by_masked_xpath)
      logger.log("Masked xpath is good: #{masked_xpath}#{collapsion_log_str} (#{masked_xpath_links.length} links)")
      best_xpath_links = masked_xpath_links
      next
    end

    reversed_masked_xpath_links = masked_xpath_links.reverse
    reversed_masked_xpath_link_urls = masked_xpath_link_canonical_urls.reverse
    if feed_item_urls == reversed_masked_xpath_link_urls[0...feed_item_urls.length]
      collapsion_log_str = get_collapsion_log_str(masked_xpath, links_by_masked_xpath, collapsed_links_by_masked_xpath)
      logger.log("Masked xpath is good in reverse order: #{masked_xpath}#{collapsion_log_str} (#{reversed_masked_xpath_links.length} links)")
      best_xpath_links = reversed_masked_xpath_links
      next
    end

    logger.log("Masked xpath #{masked_xpath} has all links #{feed_item_urls} but not in the right order: #{masked_xpath_link_canonical_urls}")
  end

  if best_xpath_links
    return { pattern: "archives", links: best_xpath_links }
  end

  if feed_item_urls.length < 3
    return nil
  end

  feed_prefix_xpaths_by_length = {}
  collapsed_links_by_masked_xpath.each do |masked_xpath, masked_xpath_links|
    next if masked_xpath_links.length >= feed_item_urls.length

    feed_item_urls.zip(masked_xpath_links).each_with_index do |pair, index|
      feed_item_url, masked_xpath_link = pair
      if index > 0 && masked_xpath_link.nil?
        prefix_length = index
        unless feed_prefix_xpaths_by_length.key?(prefix_length)
          feed_prefix_xpaths_by_length[prefix_length] = []
        end
        feed_prefix_xpaths_by_length[prefix_length] << masked_xpath
        break
      elsif feed_item_url != masked_xpath_link.canonical_url
        break # Not a prefix
      end
    end
  end

  collapsed_links_by_masked_xpath.each do |masked_xpath, masked_xpath_links|
    feed_suffix_start_index = feed_item_urls.index(masked_xpath_links[0].canonical_url)
    next if feed_suffix_start_index.nil?

    is_suffix = true
    feed_item_urls[feed_suffix_start_index..-1].zip(masked_xpath_links).each do |feed_item_url, masked_xpath_link|
      if feed_item_url.nil?
        break # suffix found
      elsif masked_xpath_link.nil?
        is_suffix = false
        break
      elsif feed_item_url != masked_xpath_link.canonical_url
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
    combined_urls = combined_links.map(&:canonical_url)
    combined_urls_set = combined_urls.to_set
    if combined_urls.length != combined_urls_set.length
      logger.log("Combination has all feed links but also duplicates: #{combined_urls}")
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
