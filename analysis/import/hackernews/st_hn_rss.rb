require 'csv'
require 'set'
require 'sqlite3'
require_relative '../../crawling/logger'
require_relative 'hn_rss'

score_cutoff = 10

logger = MyLogger.new($stdout)

urls_csv = CSV.read('up_submissions.csv')[1..]
cutoff_index = urls_csv.index { |_, sum_score, _| sum_score.to_i < score_cutoff }
if cutoff_index
  top_urls_csv = urls_csv[...cutoff_index]
else
  top_urls_csv = urls_csv
end
logger.info("#{urls_csv.length} rows total, #{top_urls_csv.length} over cutoff of #{score_cutoff}")

db = SQLite3::Database.new("hn.db")

indices_processed = db
  .execute("select row from rows_processed")
  .map(&:first)
  .map(&:to_i)
  .to_set

throttler = Throttler.new

url_index = 0
top_urls_csv.each do |url, sum_score, count|
  url_index += 1
  next unless url_index == 15770
  logger.info("#{url_index}/#{top_urls_csv.length} Url #{url}, sum_score #{sum_score}, count #{count}")
  if indices_processed.include?(url_index)
    logger.info("Url already processed")
    next
  end

  input_rows = [InputRow.new(url_index, url, sum_score.to_i, count.to_i)]
  out_feeds, out_scores, out_redirects, out_rows_processed, _ = hn_rss(input_rows, throttler, logger)

  out_feeds.each do |url, feed_url|
    db.execute(
      "insert into feeds (url, feed_url) values (?, ?)",
      [url, feed_url]
    )
  end

  out_scores.each do |url, sum_score, count|
    db.execute(
      "insert into scores (url, sum_score, count) values (?, ?, ?)",
      [url, sum_score, count]
    )
  end

  out_redirects.each do |curl, url|
    db.execute(
      "insert into redirects (prefix_curl, url) values (?, ?)",
      [curl, url]
    )
  end

  out_rows_processed.each do |index|
    db.execute("insert into rows_processed (row) values (?)", [index])
  end
end
