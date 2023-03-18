require_relative 'canonical_link'

module HardcodedBlogs
  # Blogs here have explicit branches for them in code, there are more in the database

  ACOUP = "https://acoup.blog/"
  CASEY_HANDMER = "https://caseyhandmer.wordpress.com/"
  CASEY_HANDMER_SPACE_MISCONCEPTIONS = CASEY_HANDMER + "2019/08/17/blog-series-countering-misconceptions-in-space-journalism/"
  CRYPTOGRAPHY_ENGINEERING = "https://blog.cryptographyengineering.com"
  CRYPTOGRAPHY_ENGINEERING_ALL = CRYPTOGRAPHY_ENGINEERING + "/all-posts/"
  FACTORIO = "https://www.factorio.com/blog/"
  JULIA_EVANS = "https://jvns.ca"
  MR_MONEY_MUSTACHE = "https://www.mrmoneymustache.com/blog"
  OUR_MACHINERY = "https://ourmachinery.com" # Hardcoded as fake feed, actual post Links are stored in the db
  #noinspection HttpUrlsUsage
  PAUL_GRAHAM = "http://www.aaronsw.com/2002/feeds/pgessays.rss"
  KALZUMEUS = "https://kalzumeus.com/archive/"
  BENKUHN = "https://www.benkuhn.net/all/"

  def self.is_match(link, url, curi_eq_cfg)
    canonical_uri_equal?(
      link.curi,
      CanonicalUri::from_uri(URI(url)),
      curi_eq_cfg
    )
  end
end
