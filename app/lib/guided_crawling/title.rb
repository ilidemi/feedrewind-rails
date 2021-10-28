def normalize_title(title)
  return nil if title.nil?

  stripped_title = title.strip
  return nil if stripped_title.empty?

  stripped_title.gsub(/\u00A0/, " ")
end

TITLE_EQ_SUBSTITUTIONS = [
  %w[’ '],
  %w[‘ '],
  %w[” "],
  %w[“ "],
  %w[… ...]
]

def are_titles_equal(title1, title2)
  TITLE_EQ_SUBSTITUTIONS.each do |from, to|
    title1 = title1.gsub(from, to)
    title2 = title2.gsub(from, to)
  end

  title1 == title2
end
