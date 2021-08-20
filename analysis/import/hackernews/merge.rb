require 'sqlite3'

db15 = SQLite3::Database.new("hn.db")
feeds15 = db15.execute("select url, feed_url from feeds")
scores15 = db15
  .execute("select url, sum_score, count from scores")
  .map { |url, sum_score_s, count_s| [url, sum_score_s.to_i, count_s.to_i] }

db13 = SQLite3::Database.new("hn13.db")
feeds13 = db13.execute("select url, feed_url from feeds")
scores13 = db13
  .execute("select url, sum_score, count from scores")
  .map { |url, sum_score_s, count_s| [url, sum_score_s.to_i, count_s.to_i] }

feeds = feeds15 + feeds13
scores = scores15 + scores13

score_count_by_curl = {}
scores.each do |url, sum_score, count|
  curl = url.sub(/^https?:\/\//, "")
  if score_count_by_curl.key?(curl)
    score_count_by_curl[curl][0] += sum_score
    score_count_by_curl[curl][1] += count
  else
    score_count_by_curl[curl] = [sum_score, count]
  end
end

FeedRow = Struct.new(:url, :feed_url, :sum_score, :count)

feed_row_by_curl = {}
feed_row_by_feed_curl = {}
feeds.each do |url, feed_url|
  curl = url.sub(/^https?:\/\//, "")
  next if feed_row_by_curl.key?(curl)

  feed_curl = feed_url.sub(/^https?:\/\//, "")
  if feed_row_by_feed_curl.key?(feed_curl)
    sum_score, count = score_count_by_curl[curl]
    feed_row_by_feed_curl[feed_curl].sum_score += sum_score
    feed_row_by_feed_curl[feed_curl].count += count
  else
    feed_row_by_feed_curl[feed_curl] = feed_row_by_curl[curl] =
      FeedRow.new(url, feed_url, *score_count_by_curl[curl])
  end
end

sorted_feed_rows = feed_row_by_curl.values.sort { |row1, row2| row2.sum_score <=> row1.sum_score }
puts "Total rows: #{sorted_feed_rows.length}"

File.open("feeds.csv", "w") do |feeds_f|
  feeds_f.write("url,feed_url,sum_score,count\n")
  sorted_feed_rows.each do |row|
    if row.url.include?(",")
      puts "Url with comma: #{row.url}"
      next
    end
    if row.feed_url.include?(",")
      puts "Feed url with comma: #{row.feed_url}"
      next
    end
    feeds_f.write("#{row.url},#{row.feed_url},#{row.sum_score},#{row.count}\n")
  end
end

count_by_host = feed_row_by_curl
  .keys
  .map { |curl| curl.match(/^[^\/]+/)[0] }
  .each_with_object(Hash.new(0)) { |host, hash| hash[host] += 1 }
  .sort { |host_count1, host_count2| host_count2[1] <=> host_count1[1] }

puts "Top hosts:"
count_by_host.take(50).each do |host, count|
  puts "#{host}: #{count}"
end