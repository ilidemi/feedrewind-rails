require 'json'
require 'nokogumbo'
require_relative '../db'

db = connect_db

total_pages = db.exec("select count(*) from pages where content is not null")[0]
puts "Total pages: #{total_pages}"

urls_count = 0
File.delete("urls.jsonl")
File.open("urls.jsonl", "w") do |urls_f|
  db.transaction do |transaction|
    transaction.exec("declare pages_cursor cursor for select start_link_id, fetch_url, content_type, content from pages where content is not null")

    pages_processed = 0
    loop do
      batch = transaction.exec("fetch forward 100 from pages_cursor")
      batch.each do |row|
        next if row["content_type"] != 'text/html'

        document = Nokogiri::HTML5(row["content"], max_attributes: -1)
        link_elements = document.css('a').to_a + document.css('link').to_a

        link_elements.each do |element|
          next unless element.attributes.key?('href')
          fetch_url = row["fetch_url"]
          url = element.attributes['href'].to_s
          if fetch_url.empty? && url.empty?
            puts "Skipping empty url for start link id #{row["start_link_id"]}"
            next
          end
          line_json = JSON.dump({fetch_url: fetch_url, url: url})
          urls_f.write(line_json)
          urls_f.write("\n")
          urls_count += 1
        end
        urls_f.flush
      end

      if batch.cmd_tuples == 0
        break
      end

      pages_processed += batch.cmd_tuples
      puts "#{pages_processed} #{urls_count}"
    end
  end
end

puts "Urls: #{urls_count}"
