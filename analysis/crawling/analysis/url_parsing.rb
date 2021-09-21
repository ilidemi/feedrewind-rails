require 'json'
require_relative '../../../app/lib/guided_crawling/guided_crawling'
require_relative '../logger'

logger = MyLogger.new($stdout)

File.open("urls.jsonl") do |urls_f|
  urls_f.each_line.with_index do |line, index|
    if index % 100000 == 0
      puts index
    end

    if index == 100000
      break
    end

    json_line = JSON.load(line)
    fetch_url = json_line["fetch_url"]
    url = json_line["url"]
    begin
      to_canonical_link(url, logger, URI(fetch_url))
    rescue
      puts "#{index} Bad url: #{fetch_url} #{url}"
      raise
    end
  end
end