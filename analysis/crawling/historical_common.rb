SUBPATTERN_PRIORITIES = {
  archives_1star: 1,
  archives_2star: 2,
  archives_3star: 3,
  paged: 4
}

def group_links_by_masked_xpath(page_links, feed_entry_canonical_uris_set, xpath_name, get_masked_xpaths_func)
  links_by_masked_xpath = {}
  page_feed_links = page_links
    .filter { |page_link| feed_entry_canonical_uris_set.include?(page_link.canonical_uri) }
  page_feed_links.each do |page_feed_link|
    masked_xpaths = get_masked_xpaths_func.call(page_feed_link[xpath_name])
    masked_xpaths.each do |masked_xpath|
      next if links_by_masked_xpath.key?(masked_xpath)
      links_by_masked_xpath[masked_xpath] = []
    end
  end
  page_links.each do |page_link|
    masked_xpaths = get_masked_xpaths_func.call(page_link[xpath_name])
    masked_xpaths.each do |masked_xpath|
      next unless links_by_masked_xpath.key?(masked_xpath)
      links_by_masked_xpath[masked_xpath] << page_link
    end
  end
  links_by_masked_xpath
end

def get_single_masked_xpaths(xpath)
  matches = xpath.to_enum(:scan, /\[\d+\]/).map { Regexp.last_match }
  matches.map do |match_data|
    start, finish = match_data.offset(0)
    xpath[0..start] + '*' + xpath[(finish - 1)..-1]
  end
end

def get_double_masked_xpaths(xpath)
  matches = xpath.to_enum(:scan, /\[\d+\]/).map { Regexp.last_match }
  matches.combination(2).map do |match1, match2|
    start1, finish1 = match1.offset(0)
    start2, finish2 = match2.offset(0)
    xpath[0..start1] + '*' +
      xpath[(finish1 - 1)..start2] + '*' +
      xpath[(finish2 - 1)..-1]
  end
end

def get_collapsion_log_str(masked_xpath, links_by_masked_xpath, collapsed_links_by_masked_xpath)
  collapsed_length = collapsed_links_by_masked_xpath[masked_xpath].length
  uncollapsed_length = links_by_masked_xpath[masked_xpath].length
  if uncollapsed_length != collapsed_length
    " (collapsed #{uncollapsed_length} -> #{collapsed_length})"
  else
    ''
  end
end
