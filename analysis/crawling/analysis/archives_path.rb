require_relative '../db'

db = connect_db

failing_archives_id_paths = db.exec_params(
  "select successes.start_link_id, historical_ground_truth.main_page_canonical_url from successes "\
  "natural left join historical_ground_truth "\
  "where historical_ground_truth.pattern in ('archives', 'archives_2xpaths') and "\
  "start_link_id not in (select start_link_id from guided_successes)"
).map { |row| [row["start_link_id"].to_i, row["main_page_canonical_url"]] }

archives_regex = "^(?:archives?|blog|posts|articles|writing|journal|all)(?:\\.[a-z]+)?$"
last_token_counts = Hash.new(0)
failing_archives_id_paths.each do |_, path|
  last_token = path.delete_suffix('/').split('/')[-1]
  last_token = archives_regex if last_token.match(archives_regex)
  last_token_counts[last_token] += 1
end

puts "total: #{failing_archives_id_paths.length}"
last_token_counts
  .sort_by { |_, count| -count }
  .each do |token, count|

  puts "#{token}: #{count}"
end
