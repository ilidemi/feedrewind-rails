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
    .filter { |category| !category.name.include?("Recurse center") && category.name != "Conferences" }
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

def extract_cryptography_engineering_categories(logger)
  #noinspection RubyLiteralArrayInspection
  top_posts_urls = [
    "https://blog.cryptographyengineering.com/2015/03/03/attack-of-week-freak-or-factoring-nsa/",
    "https://blog.cryptographyengineering.com/2016/03/21/attack-of-week-apple-imessage/",
    "https://blog.cryptographyengineering.com/2014/04/24/attack-of-week-triple-handshakes-3shake/",
    "https://blog.cryptographyengineering.com/2012/10/27/attack-of-week-cross-vm-timing-attacks/",
    "https://blog.cryptographyengineering.com/2013/09/06/on-nsa/",
    "https://blog.cryptographyengineering.com/2015/12/22/on-juniper-backdoor/",
    "https://blog.cryptographyengineering.com/2015/05/22/attack-of-week-logjam/",
    "https://blog.cryptographyengineering.com/2013/12/03/how-does-nsa-break-ssl/",
    "https://blog.cryptographyengineering.com/2014/12/29/on-new-snowden-documents/",
    "https://blog.cryptographyengineering.com/2013/09/18/the-many-flaws-of-dualecdrbg/",
    "https://blog.cryptographyengineering.com/2013/09/20/rsa-warns-developers-against-its-own/",
    "https://blog.cryptographyengineering.com/2013/12/28/a-few-more-notes-on-nsa-random-number/",
    "https://blog.cryptographyengineering.com/2015/01/14/hopefully-last-post-ill-ever-write-on/",
    "https://blog.cryptographyengineering.com/2014/11/27/zero-knowledge-proofs-illustrated-primer/",
    "https://blog.cryptographyengineering.com/2011/09/29/what-is-random-oracle-model-and-why-3/",
    "https://blog.cryptographyengineering.com/2011/10/08/what-is-random-oracle-model-and-why-2/",
    "https://blog.cryptographyengineering.com/2011/10/20/what-is-random-oracle-model-and-why_20/",
    "https://blog.cryptographyengineering.com/2011/11/02/what-is-random-oracle-model-and-why/",
    "https://blog.cryptographyengineering.com/2016/06/15/what-is-differential-privacy/",
    "https://blog.cryptographyengineering.com/2014/02/21/cryptographic-obfuscation-and/",
    "https://blog.cryptographyengineering.com/2013/04/11/wonkery-mailbag-ideal-ciphers/",
    "https://blog.cryptographyengineering.com/2014/10/04/why-cant-apple-decrypt-your-iphone/",
    "https://blog.cryptographyengineering.com/2014/08/13/whats-matter-with-pgp/",
    "https://blog.cryptographyengineering.com/2015/08/16/the-network-is-hostile/",
    "https://blog.cryptographyengineering.com/2012/02/28/how-to-fix-internet/",
    "https://blog.cryptographyengineering.com/2012/02/21/random-number-generation-illustrated/",
    "https://blog.cryptographyengineering.com/2012/03/09/surviving-bad-rng/",
    "https://blog.cryptographyengineering.com/2015/04/02/truecrypt-report/",
    "https://blog.cryptographyengineering.com/2013/10/14/lets-audit-truecrypt/"
  ]
  top_posts_links = top_posts_urls.map { |url| to_canonical_link(url, logger) }

  [HistoricalBlogPostCategory.new("Top posts", true, top_posts_links)]
end

def extract_casey_handmer_categories(space_misconceptions_page, logger)
  top_links = space_misconceptions_page
    .document
    .xpath("/html/body/div[1]/div/div/div[1]/main/article/div[1]/ul[*]/li[*]/a")
    .map { |element| element["href"] }
    .map { |url| to_canonical_link(url, logger) }

  [HistoricalBlogPostCategory.new("Space Misconceptions", true, top_links)]
end

def extract_kalzumeus_categories(logger)
  #noinspection RubyLiteralArrayInspection
  top_posts_urls = [
    "https://www.kalzumeus.com/2012/01/23/salary-negotiation/",
    "https://www.kalzumeus.com/2011/10/28/dont-call-yourself-a-programmer/",
    "https://www.kalzumeus.com/2011/03/13/some-perspective-on-the-japan-earthquake/",
    "https://www.kalzumeus.com/2010/08/25/the-hardest-adjustment-to-self-employment/",
    "https://www.kalzumeus.com/2010/06/17/falsehoods-programmers-believe-about-names/",
    "https://www.kalzumeus.com/2010/04/20/building-highly-reliable-websites-for-small-companies/",
    "https://www.kalzumeus.com/2010/03/20/running-a-software-business-on-5-hours-a-week/",
    "https://www.kalzumeus.com/2010/01/24/startup-seo/",
    "https://www.kalzumeus.com/2009/09/05/desktop-aps-versus-web-apps/",
    "https://www.kalzumeus.com/2009/03/07/how-to-successfully-compete-with-open-source-software/",
  ]
  top_posts_links = top_posts_urls.map { |url| to_canonical_link(url, logger) }

  [HistoricalBlogPostCategory.new("Most Popular", true, top_posts_links)]
end

def extract_benkuhn_categories(logger)
  #noinspection RubyLiteralArrayInspection
  top_posts_urls = [
    "https://www.benkuhn.net/abyss/",
    "https://www.benkuhn.net/outliers/",
    "https://www.benkuhn.net/listen/",
    "https://www.benkuhn.net/blub/",
    "https://www.benkuhn.net/attention/",
    "https://www.benkuhn.net/conviction/",
    "https://www.benkuhn.net/hard/",
    "https://www.benkuhn.net/lux/",
    "https://www.benkuhn.net/emco/",
    "https://www.benkuhn.net/autocomplete/",
    "https://www.benkuhn.net/squared/",
    "https://www.benkuhn.net/cf-plants/",
  ]
  top_posts_links = top_posts_urls.map { |url| to_canonical_link(url, logger) }

  [HistoricalBlogPostCategory.new("Essays", true, top_posts_links)]
end