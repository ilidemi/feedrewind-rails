module OnboardingHelper
  class ScreenshotLink
    def initialize(url, title, slug, blog_name, feed_url)
      @url = url
      @title = title
      @title_mobile = title.gsub("<br>", " ")
      @slug = slug
      @blog_name = blog_name
      @feed_url = feed_url
    end

    attr_reader :url, :title, :title_mobile, :slug, :blog_name, :feed_url
  end

  BlogsCategory = Struct.new(:name, :blogs)
  SuggestedBlog = Struct.new(:url, :feed_url, :name)
  MiscellaneousBlog = Struct.new(:url, :feed_url, :name, :tag)

  SCREENSHOT_LINKS = [
    ScreenshotLink.new(
      "https://www.kalzumeus.com/2012/01/23/salary-negotiation/",
      "Salary Negotiation: Make More<br>Money, Be More Valued",
      "kalzumeus-salary-negotiation",
      "Kalzumeus Software",
      "https://www.kalzumeus.com/feed/articles/",
    ),
    ScreenshotLink.new(
      "https://waitbutwhy.com/2014/05/life-weeks.html",
      "Your Life in Weeks",
      "wbw-your-life-in-weeks",
      "Wait But Why",
      "https://waitbutwhy.com/feed",
    ),
    ScreenshotLink.new(
      "https://slatestarcodex.com/2014/07/30/meditations-on-moloch/",
      "Meditations On Moloch",
      "ssc-meditations-on-moloch",
      "Slate Star Codex",
      "https://slatestarcodex.com/feed/",
    ),
    ScreenshotLink.new(
      "https://www.inkandswitch.com/local-first/",
      "Local-first software",
      "inkandswitch-local-first-software",
      "Ink & Switch",
      "https://www.inkandswitch.com/index.xml",
    ),
    ScreenshotLink.new(
      "http://www.paulgraham.com/kids.html",
      "Having Kids",
      "pg-having-kids",
      "Paul Graham: Essays",
      "http://www.aaronsw.com/2002/feeds/pgessays.rss"
    ),
    ScreenshotLink.new(
      "https://jvns.ca/blog/2020/07/14/when-your-coworker-does-great-work-tell-their-manager/",
      "When your coworker does great<br>work, tell their manager",
      "jvns-great-work",
      "Julia Evans",
      "https://jvns.ca/atom.xml",
    ),
    ScreenshotLink.new(
      "https://www.benkuhn.net/attention/",
      "Attention is your scarcest resource",
      "benkuhn-attention",
      "Ben Kuhn",
      "https://www.benkuhn.net/index.xml",
    ),
    ScreenshotLink.new(
      "https://danluu.com/look-stupid/",
      "Willingness to look stupid",
      "danluu-willingness-to-look-stupid",
      "Dan Luu",
      "https://danluu.com/atom.xml",
    ),
    ScreenshotLink.new(
      "https://ciechanow.ski/mechanical-watch/",
      "Mechanical Watch",
      "ciechanowski-mechanical-watch",
      "Bartosz Ciechanowski",
      "https://ciechanow.ski/atom.xml",
    ),
    ScreenshotLink.new(
      "https://acoup.blog/2022/08/26/collections-why-no-roman-industrial-revolution/",
      "Why No Roman Industrial Revolution?",
      "acoup-roman-industrial-revolution",
      "A Collection of Unmitigated Pedantry",
      "https://acoup.blog/feed/",
    ),
  ]

  SCREENSHOT_LINKS_BY_SLUG = SCREENSHOT_LINKS.to_h { |link| [link.slug, link] }

  SUGGESTED_CATEGORIES = [
    BlogsCategory.new(
      "Programming",
      [
        SuggestedBlog.new("https://danluu.com", "https://danluu.com/atom.xml", "Dan Luu"),
        SuggestedBlog.new("https://jvns.ca", "https://jvns.ca/atom.xml", "Julia Evans"),
        SuggestedBlog.new("https://brandur.org/articles", "https://brandur.org/articles.atom", "Brandur Leach"),
        SuggestedBlog.new("https://www.brendangregg.com/blog/", "https://www.brendangregg.com/blog/rss.xml", "Brendan Gregg"),
        SuggestedBlog.new("https://yosefk.com/blog/", "https://yosefk.com/blog/feed", "Yossi Krenin"),
        SuggestedBlog.new("https://www.reddit.com/r/gamedev/comments/wd4qoh/our_machinery_extensible_engine_made_in_c_just/", "https://ourmachinery.com", "Our Machinery"),
        SuggestedBlog.new("https://www.factorio.com/blog/", "https://www.factorio.com/blog/rss", "Factorio")
      ]
    ),
    BlogsCategory.new(
      "Machine Learning",
      [
        SuggestedBlog.new("https://karpathy.github.io", "https://karpathy.github.io/feed.xml", "Andrej Karpathy"),
        SuggestedBlog.new("https://distill.pub/", "https://distill.pub/rss.xml", "Distill"),
        SuggestedBlog.new("https://openai.com/blog/", "https://openai.com/blog/rss/", "OpenAI"),
        SuggestedBlog.new("https://bair.berkeley.edu/blog/", "https://bair.berkeley.edu/blog/feed.xml", "BAIR"),
        SuggestedBlog.new("https://www.deepmind.com/blog", "https://www.deepmind.com/blog/rss.xml", "DeepMind")
      ]
    ),
    BlogsCategory.new(
      "Rationality",
      [
        SuggestedBlog.new("https://slatestarcodex.com/", "https://slatestarcodex.com/feed/", "Slate Star Codex"),
        SuggestedBlog.new("https://applieddivinitystudies.com/", "https://applieddivinitystudies.com/atom.xml", "Applied Divinity Studies"),
        SuggestedBlog.new("https://dynomight.net/", "https://dynomight.net/feed.xml", "DYNOMIGHT"),
        SuggestedBlog.new("https://sideways-view.com/", "https://sideways-view.com/feed/", "The sideways view"),
        SuggestedBlog.new("https://meltingasphalt.com/", "https://feeds.feedburner.com/MeltingAsphalt", "Melting Asphalt"),
      ]
    )
  ]

  #noinspection HttpUrlsUsage
  MISCELLANEOUS_BLOGS = [
    MiscellaneousBlog.new("https://acoup.blog/", "https://acoup.blog/feed/", "A Collection of Unmitigated Pedantry", "history"),
    MiscellaneousBlog.new("https://pedestrianobservations.com/", "https://pedestrianobservations.com/feed/", "Pedestrian Observations", "urbanism"),
    MiscellaneousBlog.new("http://paulgraham.com/articles.html", "http://www.aaronsw.com/2002/feeds/pgessays.rss", "Paul Graham", "entrepreneurship"),
    MiscellaneousBlog.new("https://caseyhandmer.wordpress.com/", "https://caseyhandmer.wordpress.com/feed/", "Casey Handmer", "space"),
    MiscellaneousBlog.new("https://waitbutwhy.com/archive", "https://waitbutwhy.com/feed", "Wait But Why", "life"),
    MiscellaneousBlog.new("https://www.mrmoneymustache.com/", "https://feeds.feedburner.com/mrmoneymustache", "Mr. Money Mustache", "personal finance"),
    MiscellaneousBlog.new("https://blog.cryptographyengineering.com/", "https://blog.cryptographyengineering.com/feed/", "Cryptographic Engineering", "cryptography"),
    MiscellaneousBlog.new("https://www.righto.com/", "https://www.righto.com/feeds/posts/default", "Ken Shirriff", "hardware"),
    MiscellaneousBlog.new("https://daniellakens.blogspot.com/", "https://daniellakens.blogspot.com/feeds/posts/default", "The 20% Statistician", "statistics"),
  ]

  def OnboardingHelper.preview_path(link)
    "/preview/#{link.slug}"
  end
end
