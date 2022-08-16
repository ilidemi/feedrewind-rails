require_relative 'canonical_link'

HistoricalBlogPostCategory = Struct.new(:name, :is_top, :post_links)

def extract_jvns_categories(page, logger)
  logger.info("Extracting jvns categories")

  categories = []
  headings = page.document.xpath("//article/a/h3").to_a
  headings.each do |heading|
    category_name = heading.content.strip
    post_html_links = heading.parent.next.xpath(".//a")
    post_links = post_html_links.map do |link|
      to_canonical_link(link["href"], logger, page.fetch_uri)
    end

    categories << HistoricalBlogPostCategory.new(category_name, false, post_links)
  end

  post_links_except_rc = categories
    .filter { |category| !category.name.include?("Recurse center") }
    .flat_map { |category| category.post_links }

  categories.prepend(HistoricalBlogPostCategory.new("Everything", true, []))
  categories.prepend(HistoricalBlogPostCategory.new("Blog posts", true, post_links_except_rc))

  categories_strs = categories.map { |category| "#{category.is_top ? "!" : ""}#{category.name} (#{category.post_links.length})"}
  logger.info("jvns categories: #{categories_strs.join(", ")}")
  categories
end
