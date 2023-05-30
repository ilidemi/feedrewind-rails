LinkTitle = Struct.new(:value, :equalized_value, :source, :alternative_values_by_source)

def create_link_title(value, source, alternative_values_by_source = nil)
  raise "Link title value can't be null" unless value

  LinkTitle.new(value, equalize_title(value), source, alternative_values_by_source)
end

def print_title_source(title_source)
  if title_source.is_a?(Symbol)
    ":#{title_source}"
  else
    title_source.to_s
  end
end

def print_title(link_title)
  if link_title.alternative_values_by_source
    alternatives = ", alternatives: #{link_title.alternative_values_by_source}"
  else
    alternatives = ""
  end
  "\"#{link_title.value}\" (#{print_title_source(link_title.source)}#{alternatives})"
end

def get_page_title(page, feed_generator)
  og_title = page.document.xpath("/html/head/meta[@property='og:title'][@content]").first
  if feed_generator != :tumblr && og_title
    normalize_title(og_title["content"])
  else
    normalize_title(page.document.title)
  end
end

def normalize_title(title)
  return nil if title.nil?

  stripped_title = title.strip
  return nil if stripped_title.empty?

  stripped_title
    .gsub(/\u00A0/, " ") # Non-breaking space
    .gsub(/\r\n|\r|\n/, " ")
    .gsub(/ +/, " ")
end

TITLE_EQ_SUBSTITUTIONS = [
  %w[’ '],
  %w[‘ '],
  %w[” "],
  %w[“ "],
  %w[… ...],
  ["\u200A", " "] # Hair space
]

def equalize_title(title)
  return title if title.nil?

  TITLE_EQ_SUBSTITUTIONS.each do |from, to|
    title = title.gsub(from, to)
  end

  title.downcase
end

def are_titles_equal(title1, title2)
  return false if title1.nil?
  return false if title2.nil?

  equalize_title(title1) == equalize_title(title2)
end

ENDS_WITH_ELLIPSIS_REGEX = /\A(.+)(\.\.\.|…)\z/

def are_titles_roughly_equal(title1, title2)
  return false if title1.nil?
  return false if title2.nil?
  return true if equalize_title(title1) == equalize_title(title2)

  title1_ellipsis_match = title1.match(ENDS_WITH_ELLIPSIS_REGEX)
  title2_ellipsis_match = title2.match(ENDS_WITH_ELLIPSIS_REGEX)
  if title1_ellipsis_match && title2_ellipsis_match
    title1_ellipsis_match[1].start_with?(title2_ellipsis_match[1]) ||
      title2_ellipsis_match[1].start_with?(title1_ellipsis_match[1])
  elsif title1_ellipsis_match
    title2.start_with?(title1_ellipsis_match[1])
  elsif title2_ellipsis_match
    title1.start_with?(title2_ellipsis_match[1])
  else
    false
  end
end

def get_element_title(element)
  # Nokogiri's .inner_text removes <br> without inserting any whitespace. Insert newlines manually instead.
  def get_element_inner_text(element)
    return element.inner_text if element.text?

    tokens = []
    element.children.each do |child|
      if child.element? && child.name == "br"
        tokens << "\n"
      else
        tokens << get_element_inner_text(child)
      end
    end

    tokens.join("")
  end

  raw_title = get_element_inner_text(element)
  normalize_title(raw_title)
end