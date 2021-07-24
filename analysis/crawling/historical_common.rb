XpathTreeNode = Struct.new(:xpath_segments, :children, :parent, :is_link, :is_feed_link)

def group_links_by_masked_xpath(page_links, feed_entry_canonical_uris_set, xpath_name, star_count)
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
      feed_entry_canonical_uris_set.include?(page_link.canonical_uri)
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

def get_collapsion_log_str(masked_xpath, links_by_masked_xpath, collapsed_links_by_masked_xpath)
  collapsed_length = collapsed_links_by_masked_xpath[masked_xpath].length
  uncollapsed_length = links_by_masked_xpath[masked_xpath].length
  if uncollapsed_length != collapsed_length
    " (collapsed #{uncollapsed_length} -> #{collapsed_length})"
  else
    ''
  end
end
