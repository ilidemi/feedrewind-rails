require_relative 'canonical_link'

HistoricalBlogPostCategory = Struct.new(:name, :is_top, :post_links)

def category_counts_to_s(categories)
  categories
    .map { |category| "#{category.is_top ? "!" : ""}#{category.name} (#{category.post_links.length})" }
    .join(", ")
end

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
  categories.prepend(HistoricalBlogPostCategory.new("Blog posts", true, post_links_except_rc))
  categories
end

def extract_pg_categories(logger)
  #noinspection RubyLiteralArrayInspection,HttpUrlsUsage
  top_urls = [
    "http://www.paulgraham.com/hs.html",
    "http://www.paulgraham.com/essay.html",
    "http://www.paulgraham.com/marginal.html",
    "http://www.paulgraham.com/jessica.html",
    "http://www.paulgraham.com/lies.html",
    "http://www.paulgraham.com/wisdom.html",
    "http://www.paulgraham.com/wealth.html",
    "http://www.paulgraham.com/re.html",
    "http://www.paulgraham.com/say.html",
    "http://www.paulgraham.com/makersschedule.html",
    "http://www.paulgraham.com/ds.html",
    "http://www.paulgraham.com/vb.html",
    "http://www.paulgraham.com/love.html",
    "http://www.paulgraham.com/growth.html",
    "http://www.paulgraham.com/startupideas.html",
    "http://www.paulgraham.com/mean.html",
    "http://www.paulgraham.com/kids.html",
    "http://www.paulgraham.com/lesson.html",
    "http://www.paulgraham.com/hwh.html",
    "http://www.paulgraham.com/think.html",
    "http://www.paulgraham.com/worked.html",
    "http://www.paulgraham.com/heresy.html",
    "http://www.paulgraham.com/newideas.html",
    "http://www.paulgraham.com/useful.html",
    "http://www.paulgraham.com/richnow.html",
    "http://www.paulgraham.com/cred.html",
    "http://www.paulgraham.com/own.html",
    "http://www.paulgraham.com/smart.html",
    "http://www.paulgraham.com/wtax.html",
    "http://www.paulgraham.com/conformism.html",
    "http://www.paulgraham.com/orth.html",
    "http://www.paulgraham.com/noob.html",
    "http://www.paulgraham.com/early.html",
    "http://www.paulgraham.com/ace.html",
    "http://www.paulgraham.com/simply.html",
    "http://www.paulgraham.com/fn.html",
    "http://www.paulgraham.com/earnest.html",
    "http://www.paulgraham.com/genius.html",
    "http://www.paulgraham.com/work.html",
    "http://www.paulgraham.com/before.html"
  ]
  top_links = top_urls.map { |url| to_canonical_link(url, logger) }

  [HistoricalBlogPostCategory.new("Top", true, top_links)]
end

def extract_mm_categories(logger)
  #noinspection RubyLiteralArrayInspection
  start_here_urls = [
    "https://www.mrmoneymustache.com/2011/04/06/meet-mr-money-mustache/",
    "https://www.mrmoneymustache.com/2012/06/01/raising-a-family-on-under-2000-per-year/",
    "https://www.mrmoneymustache.com/2011/09/15/a-brief-history-of-the-stash-how-we-saved-from-zero-to-retirement-in-ten-years/",
    "https://www.mrmoneymustache.com/2011/05/12/the-coffee-machine-that-can-pay-for-a-university-education/",
    "https://www.mrmoneymustache.com/2013/02/07/interview-with-a-ceo-ridiculous-student-loans-vs-the-future-of-education/",
    "https://www.mrmoneymustache.com/2012/01/13/the-shockingly-simple-math-behind-early-retirement/",
    "https://www.mrmoneymustache.com/2011/10/02/what-is-stoicism-and-how-can-it-turn-your-life-to-solid-gold/",
    "https://www.mrmoneymustache.com/2012/09/18/is-it-convenient-would-i-enjoy-it-wrong-question/",
    "https://www.mrmoneymustache.com/2012/10/08/how-to-go-from-middle-class-to-kickass/",
    "https://www.mrmoneymustache.com/2012/03/07/frugality-the-new-fanciness/",
    "https://www.mrmoneymustache.com/2012/04/18/news-flash-your-debt-is-an-emergency/",
    "https://www.mrmoneymustache.com/2011/10/06/the-true-cost-of-commuting/",
    "https://www.mrmoneymustache.com/2011/09/28/get-rich-with-moving-to-a-better-place/",
    "https://www.mrmoneymustache.com/2011/11/28/new-cars-and-auto-financing-stupid-or-sensible/",
    "https://www.mrmoneymustache.com/2012/03/19/top-10-cars-for-smart-people/",
    "https://www.mrmoneymustache.com/2011/04/18/get-rich-with-bikes/",
    "https://www.mrmoneymustache.com/2011/05/06/mmm-challenge-cut-your-cash-leaking-umbilical-cord/",
    "https://www.mrmoneymustache.com/2012/03/29/killing-your-1000-grocery-bill/",
    "https://www.mrmoneymustache.com/2011/10/12/avoiding-ivy-league-preschool-syndrome/",
    "https://www.mrmoneymustache.com/coveragecritic/",
    "https://www.mrmoneymustache.com/2011/12/05/muscle-over-motor/",
    "https://www.mrmoneymustache.com/2012/10/03/the-practical-benefits-of-outrageous-optimism/",
    "https://www.mrmoneymustache.com/2011/05/18/how-to-make-money-in-the-stock-market/",
    "https://www.mrmoneymustache.com/2012/05/29/how-much-do-i-need-for-retirement/",
    "https://www.mrmoneymustache.com/2012/06/07/safety-is-an-expensive-illusion/",
    "https://www.mrmoneymustache.com/2011/10/17/its-all-about-the-safety-margin/"
  ]
  start_here_links = start_here_urls.map { |url| to_canonical_link(url, logger) }

  [HistoricalBlogPostCategory.new("Start Here", true, start_here_links)]
end

def extract_factorio_categories(post_links)
  fff_links = post_links.filter { |link| link.curi.path.start_with?("/blog/post/fff-") }
  [HistoricalBlogPostCategory.new("Friday Facts", true, fff_links)]
end

def extract_acoup_categories(post_links)
  articles_links = post_links.filter do |link|
    !/\/\d+\/\d+\/\d+\/(gap-week|fireside)-/.match(link.curi.path)
  end
  [HistoricalBlogPostCategory.new("Articles", true, articles_links)]
end