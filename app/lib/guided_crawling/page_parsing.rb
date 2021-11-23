require 'nokogiri'
require_relative 'canonical_link'
require_relative 'util'

def extract_links(
  document, fetch_uri, allowed_hosts, redirects, logger, include_xpath = false, include_class_xpath = false
)
  return [] unless document

  link_elements = document.xpath('//a').to_a +
    document.xpath('//link[@rel="next"]').to_a +
    document.xpath('//link[@rel="prev"]').to_a +
    document.xpath('//area').to_a
  links = []
  classes_by_xpath = {}
  link_elements.each do |element|
    link = html_element_to_link(
      element, fetch_uri, document, classes_by_xpath, redirects, logger, include_xpath, include_class_xpath
    )
    next if link.nil?
    if allowed_hosts.nil? || allowed_hosts.include?(link.uri.host)
      links << link
    end
  end

  links
end

def parse_html5(content, logger)
  document = Nokogiri::HTML5(content, max_attributes: -1, max_tree_depth: -1)
  #noinspection RubyResolve
  document.remove_namespaces!

  # Remove links with empty content as some bloggers hide links this way in favor of other links,
  # which messes up the layout
  # E.g. search for 'wikipedia' on https://maryrosecook.com/blog/archive
  removed_links_count = 0
  document.xpath("//a").each do |link_element|
    if link_element.children.empty? && is_str_nil_or_empty(link_element["aria-label"])
      link_element.unlink
      removed_links_count += 1
    end
  end

  if removed_links_count > 0
    logger.info("Removed #{removed_links_count} empty links")
  end

  document
end

def html_element_to_link(
  element, fetch_uri, document, classes_by_xpath, redirects, logger, include_xpath = false,
  include_class_xpath = false
)
  return nil unless element.key?('href')

  url_attribute = element['href']
  link = to_canonical_link(url_attribute.to_s, logger, fetch_uri)
  return nil if link.nil?

  link = follow_cached_redirects(link, redirects).clone
  link.element = element

  if include_xpath
    link.xpath = to_canonical_xpath(element.path)
  end

  if include_class_xpath
    link.class_xpath = to_class_xpath(element.path, document, fetch_uri, classes_by_xpath, logger)
    return nil unless link.class_xpath
  end

  link
end

XPATH_TOKEN_WITHOUT_INDEX_REGEX = Regexp.new("(/[^/^\\[^\\]]+)(?=/|$)")

def to_canonical_xpath(xpath)
  xpath.gsub(XPATH_TOKEN_WITHOUT_INDEX_REGEX, '\1[1]')
end

CLASS_BLACKLIST_REGEX = Regexp.new("^post-\\d+$")

CLASS_SUBSTITUTIONS = {
  '/' => '%2F',
  '[' => '%5B',
  ']' => '%5D',
  '(' => '%28',
  ')' => '%29'
}

def to_class_xpath(xpath, document, fetch_uri, classes_by_xpath, logger)
  xpath_tokens = xpath.split('/')[1..]
  prefix_xpath = ""
  class_xpath_tokens = xpath_tokens.map do |token|
    bracket_index = token.index("[")
    if bracket_index
      prefix_xpath += "/#{token}"
    else
      prefix_xpath += "/#{token}[1]"
    end

    if classes_by_xpath.key?(prefix_xpath)
      classes = classes_by_xpath[prefix_xpath]
    else
      begin
        ancestor = document.at_xpath(prefix_xpath)
      rescue Nokogiri::XML::XPath::SyntaxError, NoMethodError => e
        logger.info("Invalid XPath on page #{fetch_uri}: #{prefix_xpath} has #{e}, skipping this link")
        return nil
      end

      ancestor_classes = ancestor["class"]
      if ancestor_classes
        classes = classes_by_xpath[prefix_xpath] = ancestor_classes
          .split(' ')
          .filter { |klass| !klass.match?(CLASS_BLACKLIST_REGEX) }
          .map { |klass| klass.gsub(/[\/\[\]()]/, CLASS_SUBSTITUTIONS) }
          .sort
          .join(',')
      else
        classes = classes_by_xpath[prefix_xpath] = ''
      end
    end

    if bracket_index
      "/#{token[...bracket_index]}(#{classes})#{token[bracket_index..]}"
    else
      "/#{token}(#{classes})[1]"
    end
  end

  class_xpath_tokens.join("")
end

def follow_cached_redirects(initial_link, redirects, seen_urls = nil)
  link = initial_link
  if seen_urls.nil?
    seen_urls = [link.url]
  end
  while redirects && redirects.key?(link.url) && link.url != redirects[link.url].url
    redirection_link = redirects[link.url]
    if seen_urls.include?(redirection_link.url)
      raise "Circular redirect for #{initial_link.url}: #{seen_urls} -> #{redirection_link.url}"
    end
    seen_urls << redirection_link.url
    link = redirection_link
  end
  link
end
