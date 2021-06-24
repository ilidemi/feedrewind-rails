require 'readline'
require 'set'
require_relative '../db'

filename = '../notes/6-23_patterns_3.txt'

mode = :initial
type_operations = []
id_operations = []
issue_operations = []
BadFields = Struct.new(:id, :pattern, :count, :main_url, :oldest_url)
bad_fields = BadFields.new
IssueFields = Struct.new(:id, :severity, :issue)
issue_fields = IssueFields.new

File.open(filename) do |patterns_file|
  patterns_file.each_line do |line|
    line.strip!
    if line.downcase == 'good'
      mode = :good
    elsif line.downcase == 'new'
      mode = :new
    elsif line.downcase == 'issues'
      mode = :issues
    elsif line.downcase == 'bad'
      mode = :bad
    else
      case mode
      when :initial
        next if line.empty?
        raise "Mode not set"
      when :good
        next if line.empty?
        good_id = line.to_i
        raise "Bad id: #{line}" if good_id.nil?
        id_operations << ['insert into historical_ground_truth select * from historical where start_link_id = $1', [good_id]]
      when :issues
        if line.empty? && issue_fields.id
          raise "Issue fields are inconsistent around id #{issue_fields.id}"
        elsif line.empty?
          next
        elsif !issue_fields.id
          issue_fields.id = line.to_i
          raise "Bad id: #{line}" if issue_fields.id.nil?
        elsif !issue_fields.severity
          issue_fields.severity = line
        elsif !issue_fields.issue
          issue_fields.issue = line
          issue_operations << [
            "insert into known_issues (start_link_id, severity, issue) values ($1, $2, $3)",
            [issue_fields.id, issue_fields.severity, issue_fields.issue]
          ]
          issue_fields = IssueFields.new
        end
      when :new
        next if line.empty?
        type_operations << ["alter type pattern add value '#{line}'", []]
      when :bad
        if line.empty? && bad_fields.id
          raise "Bad fields are inconsistent around id #{bad_fields.id}"
        elsif line.empty?
          next
        elsif !bad_fields.id
          bad_fields.id = line.to_i
          raise "Bad id: #{line}" if bad_fields.id.nil?
        elsif !bad_fields.pattern
          bad_fields.pattern = line
        elsif !bad_fields.count
          bad_fields.count = line.to_i
          raise "Bad count: #{line}" if bad_fields.count.nil?
        elsif !bad_fields.main_url
          bad_fields.main_url = line
        elsif !bad_fields.oldest_url
          bad_fields.oldest_url = line
          id_operations << [
            'insert into historical_ground_truth (start_link_id, pattern, entries_count, main_page_canonical_url, oldest_entry_canonical_url) values ($1, $2, $3, $4, $5)',
            [bad_fields.id, bad_fields.pattern, bad_fields.count, bad_fields.main_url, bad_fields.oldest_url]
          ]
          bad_fields = BadFields.new
        end
      else
        raise "Unknown mode: #{mode}"
      end
    end
  end
end

if bad_fields.id
  raise "Bad fields are inconsistent around id #{bad_fields.id}"
end

if issue_fields.id
  raise "Issue fields are inconsistent around id #{issue_fields.id}"
end

def validate_ids(db, new_ids, table_name)
  return if new_ids.empty?
  new_id_counts = new_ids.each_with_object(Hash.new(0)) { |word, counts| counts[word] += 1 }
  new_id_counts.each do |id, count|
    raise "Duplicate #{table_name} id #{id}" if count > 1
  end

  in_sql = new_ids.length.times.map { |index| "$#{index + 1}::INT" }.join(",")
  clashing_ids = db
    .exec_params("select start_link_id from #{table_name} where start_link_id in (#{in_sql})", new_ids)
    .map { |row| row["start_link_id"].to_i }
  unless clashing_ids.empty?
    raise "Ids already exist in #{table_name}: #{clashing_ids}"
  end
end

db = connect_db
validate_ids(
  db,
  id_operations.map { |operation| operation[1][0] },
  'historical_ground_truth'
)

validate_ids(
  db,
  issue_operations.map { |operation| operation[1][0] },
  'known_issues'
)


puts "Operations will be performed:"
type_operations.each do |operation|
  puts operation.to_s
end
issue_operations.each do |operation|
  puts operation.to_s
end
id_operations.each do |operation|
  puts operation.to_s
end

while (buf = Readline.readline("Y/N> "))
  buf.strip!
  if buf.downcase == "y"
    break
  elsif buf.downcase == "n"
    raise "Operation aborted"
  end
end

type_operations.each do |operation|
  type = operation[0].rpartition("'")[0].rpartition("'")[2]
  result = db.exec_params(operation[0], operation[1])
  puts type
  result.check
end

failed_issue_ids = []
issue_operations.each do |operation|
  id = operation[1][0]
  result = db.exec_params(operation[0], operation[1])
  puts "#{id} #{result.cmd_status} #{result.cmd_tuples}"
  if result.cmd_tuples != 1
    failed_issue_ids << id
  end
end

failed_historical_ids = []
id_operations.each do |operation|
  id = operation[1][0]
  result = db.exec_params(operation[0], operation[1])
  puts "#{id} #{result.cmd_status} #{result.cmd_tuples}"
  if result.cmd_tuples != 1
    failed_historical_ids << id
  end
end

unless failed_issue_ids.empty?
  raise "Insert failed for issue ids: #{failed_issue_ids}"
end

unless failed_historical_ids.empty?
  raise "Insert failed for historical ids: #{failed_historical_ids}"
end
