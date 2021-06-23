require 'nokogumbo'
require 'set'
require_relative '../crawling'
require_relative '../db'
require_relative '../logger'

db = connect_db
logger = MyLogger.new($stdout)

# Needs to be changed:
# If feed is not there or there but not as alternate link, replace with rss
# If feed has multiple alternate links, insert some of feeds as rss - but after manual review
# Let's say read initial page, look at alternate, sort into 0-1-many

start_link_urls_sources = db
  .exec("select id, source_id, url from start_links where id not in (select start_link_id as id from known_issues where severity = 'discard')")
  .map { |row| [row["id"].to_i, row["url"], %w[expand feedly blaggregator][row["source_id"].to_i - 1]] }

no_feed_ids = []
single_feed_ids = []
single_reasonable_feed_url_by_id = {}
multiple_feeds_by_id = {}

start_link_urls_sources.each do |id, start_url, _|
  canonical_url = to_canonical_link(start_url, logger).canonical_url
  page_rows = db.exec_params(
    "select content from mock_pages where start_link_id = $1 and canonical_url = $2",
    [id, canonical_url]
  )
  if page_rows.cmd_tuples == 0
    no_feed_ids << id
    next
  end

  if page_rows.cmd_tuples > 1
    no_feed_ids << id
    next
  end

  page_content = unescape_bytea(page_rows.first["content"])
  html = Nokogiri::HTML5(page_content)
  feed_links = html
    .xpath("/html/head/link[@rel='alternate']")
    .to_a
    .filter { |link| %w[application/rss+xml application/atom+xml].include?(link.attributes["type"]&.value) }

  if feed_links.empty?
    no_feed_ids << id
  elsif feed_links.length == 1
    single_feed_ids << id
  else
    feed_reasonable_urls = feed_links
      .map { |link| link.attributes["href"]&.value }
      .map { |url| to_canonical_link(url, logger, URI(start_url)).url }
      .filter { |url| !url&.end_with?("?alt=rss") }
      .filter { |url| !url&.end_with?("/comments/feed/") }
    if feed_reasonable_urls.length == 1
      single_reasonable_feed_url_by_id[id] = feed_reasonable_urls.first
    else
      multiple_feeds_by_id[id] = feed_reasonable_urls
    end
  end
end

blaggregator_rss_by_url = File
  .open("../../import/blaggregator/links_rss.csv")
  .to_h { |line| line.split(";")[0..1] }

no_feed_my_ids = []
no_feed_blaggregator_ids = []
feed_recovered_blaggregator_ids = []
start_url_source_by_id = start_link_urls_sources.to_h { |id, start_url, source| [id, [start_url, source]] }
no_feed_ids.each do |id|
  start_url, source = start_url_source_by_id[id]

  if source == "blaggregator"
    blaggregator_rss = blaggregator_rss_by_url[start_url]
    if blaggregator_rss.nil?
      no_feed_blaggregator_ids << id
    else
      feed_recovered_blaggregator_ids << id
    end
  else
    no_feed_my_ids << id
  end
end

my_ids_manual_rss = {
  54 => "https://macwright.com/rss.xml",
  83 => "https://journal.stuffwithstuff.com/rss.xml",
  106 => "https://waitbutwhy.com/feed",
  109 => "https://blog.codinghorror.com/rss/",
  122 => "https://dilbert.com/feed",
  123 => "https://xkcd.com/atom.xml",
  130 => "http://n-gate.com/index.atom",
  108 => "https://simonschreibt.de/feed/",
  9 => "https://michaelnielsen.org/blog/feed/",
  5 => "https://www.datadoghq.com/blog/engineering/index.xml",
  11 => "https://martinfowler.com/feed.atom",
  32 => "https://brooker.co.za/blog/rss.xml",
  33 => "https://dropbox.tech/feed",
  37 => "https://deepmind.com/blog/feed/basic/",
  42 => "http://www.ilikebigbits.com/blog?format=RSS",
  47 => "http://blog.mozilla.com/futurereleases/feed/",
  50 => "http://www.aaronsw.com/2002/feeds/pgessays.rss",
  59 => "http://blog.mozilla.com/security/feed/",
  63 => "http://danluu.com/atom.xml",
  64 => "http://blog.khinsen.net/feeds/all.rss.xml",
  66 => "https://stratechery.com/feed/",
  67 => "https://jlongster.com/atom.xml",
  71 => "http://colah.github.io/rss.xml",
  75 => "http://www.sarahmei.com/blog/feed/",
  78 => "http://engineering.twitter.com/feeds/posts/default",
  86 => "https://www.seattletimes.com/seattle-news/data/feed/",
  93 => "http://feeds.feedburner.com/BenNorthrop",
  94 => "https://scattered-thoughts.net/rss.xml",
  95 => "https://medium.learningbyshipping.com/feed",
  99 => "https://stripe.com/blog/feed.rss",
  100 => "http://minimaxir.com/rss.xml",
  107 => "https://alex.dzyoba.com/feed",
  113 => "https://nadiaeghbal.com/feed.xml",
  114 => "https://medium.com/feed/medium-eng",
  117 => "http://dangrover.com/feed.xml",
  119 => "https://nickcraver.com/blog/feed.xml",
  120 => "http://officialandroid.blogspot.com/feeds/posts/default"
}

blaggregator_ids_manual_rss = {
  174 => "https://syncretism.xyz/jproz/feed",
  191 => "http://maciejjaskowski.github.io/feed.xml",
  209 => "https://arpith.co/feed.xml",
  299 => "https://NQNStudios.github.io/feed.xml",
  242 => "http://danielmendel.github.io/atom.xml",
  505 => "http://blog.mirkoklukas.com/feed/",
  149 => "https://writing.natwelch.com/feed.rss",
  153 => "https://blog.printf.net/feed/atom/",
  155 => "https://blog.plover.com/index.rss",
  176 => "https://jasdev.me/atom.xml",
  194 => "https://www.danielputtick.com/feeds/atom.xml",
  199 => "http://pnasrat.github.io/atom.xml",
  203 => "http://pjf.id.au/feed.xml",
  380 => "http://feeds.feedburner.com/laurensperber",
  361 => "https://blog.michelletorres.mx/feed",
  388 => "http://emmasmith.me/rss.xml",
  395 => "https://amontalenti.com/feed",
  436 => "https://imranmalek.com/feeds/all.atom.xml",
  445 => "https://www.leonlinsx.com/feed.xml",
  469 => "http://www.metafilter.com/user/98835/postsrss",
  499 => "https://rileyjshaw.com/blog-internal.xml",
  533 => "https://www.greghendershott.com/feeds/all.atom.xml",
  534 => "https://flowerhack.dreamwidth.org/data/rss",
  528 => "https://www.joeschwartz.com/feed/",
  310 => "http://danielmendel.github.io/atom.xml"
}

blaggregator_new_entries = {
  176 => ["https://jasdev.me/notes.xml"],
  194 => ["https://www.danielputtick.com/feeds/writing.atom.xml", "https://www.danielputtick.com/feeds/journal.atom.xml"],
  499 => ["https://rileyjshaw.com/blog.xml", "https://rileyjshaw.com/lab.xml", "https://rileyjshaw.com/index.xml"]
}

manual_feed_my_ids, no_manual_feed_my_ids = no_feed_my_ids.partition { |id| my_ids_manual_rss.key?(id) }
manual_feed_blaggregator_ids, no_manual_feed_blaggregator_ids = no_feed_blaggregator_ids.partition { |id| blaggregator_ids_manual_rss.key?(id) }
manual_multiple_feeds_by_id, still_multiple_feeds_by_id = multiple_feeds_by_id.partition { |id, _| blaggregator_ids_manual_rss.key?(id) || my_ids_manual_rss.key?(id) }

logger.log("Blaggregator ids with recoverable feed: #{feed_recovered_blaggregator_ids}")
logger.log("Single feed ids: #{single_feed_ids}")
logger.log("Single reasonable feed ids: #{single_reasonable_feed_url_by_id.keys}")
logger.log("Manual feed my ids: #{manual_feed_my_ids}")
logger.log("Manual feed blaggregator ids: #{manual_feed_blaggregator_ids}")
logger.log("Manual multiple feeds: #{manual_multiple_feeds_by_id}")

url_by_id = start_link_urls_sources.to_h { |id, start_url, _| [id, start_url] }
logger.log("No manual feed my ids:")
no_manual_feed_my_ids.each do |id|
  logger.log("#{id} (#{url_by_id[id]})")
end
logger.log("No manual feed blaggregator ids:")
no_manual_feed_blaggregator_ids.each do |id|
  logger.log("#{id} (#{url_by_id[id]})")
end
logger.log("Still multiple feed ids:")
still_multiple_feeds_by_id.each do |id, feed_urls|
  logger.log("#{id} (#{url_by_id[id]}) -> #{feed_urls}")
end

File.open("fix_bad_rss.sql", "w") do |sql_f|
  sql_f.puts("alter table start_links add column rss_url text;")

  sql_f.puts("-- single reasonable feeds")
  single_reasonable_feed_url_by_id.each do |id, rss_url|
    sql_f.puts("update start_links set rss_url = '#{rss_url}' where id = #{id};")
  end

  sql_f.puts("-- recovered blaggregator feeds")
  feed_recovered_blaggregator_ids.each do |id|
    rss_url = blaggregator_rss_by_url[url_by_id[id]]
    sql_f.puts("update start_links set rss_url = '#{rss_url}' where id = #{id};")
  end

  sql_f.puts("-- my manual feeds")
  my_ids_manual_rss.each do |id, rss_url|
    sql_f.puts("update start_links set rss_url = '#{rss_url}' where id = #{id};")
  end

  sql_f.puts("-- blaggregator manual feeds")
  blaggregator_ids_manual_rss.each do |id, rss_url|
    sql_f.puts("update start_links set rss_url = '#{rss_url}' where id = #{id};")
  end

  sql_f.puts("-- blaggregator new entries")
  blaggregator_new_entries.each do |orig_id, rss_urls|
    start_url = url_by_id[orig_id]
    rss_urls.each do |rss_url|
      sql_f.puts("insert into start_links (source_id, url, rss_url) values(3, '#{start_url}', '#{rss_url}');")
    end
  end
end