def group_links_by_masked_xpath(page_links, feed_item_urls_set, xpath_name, get_masked_xpaths_func)
  links_by_masked_xpath = {}
  page_feed_links = page_links.filter { |page_link| feed_item_urls_set.include?(page_link.canonical_url) }
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

def get_collapsion_log_str(masked_xpath, links_by_masked_xpath, collapsed_links_by_masked_xpath)
  collapsed_length = collapsed_links_by_masked_xpath[masked_xpath].length
  uncollapsed_length = links_by_masked_xpath[masked_xpath].length
  if uncollapsed_length != collapsed_length
    " (collapsed #{uncollapsed_length} -> #{collapsed_length})"
  else
    ''
  end
end