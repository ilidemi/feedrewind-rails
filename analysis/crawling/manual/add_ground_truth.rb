require 'readline'
require 'set'
require_relative '../db'

filename = '../notes/6-14_patterns_2.txt'

mode = :initial
type_operations = []
id_operations = []
BadFields = Struct.new(:id, :pattern, :count, :main_url, :oldest_url)
bad_fields = BadFields.new

File.open(filename) do |patterns_file|
  patterns_file.each_line do |line|
    line.strip!
    if line.downcase == 'good'
      mode = :good
    elsif line.downcase == 'new'
      mode = :new
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

new_ids = id_operations.map { |operation| operation[1][0] }
new_id_counts = new_ids.each_with_object(Hash.new(0)) { |word, counts| counts[word] += 1 }
new_id_counts.each do |id, count|
  raise "Duplicate id #{id}" if count > 1
end

db = connect_db
in_sql = new_ids.length.times.map { |index| "$#{index + 1}::INT" }.join(",")
clashing_ids = db
  .exec_params("select start_link_id from historical_ground_truth where start_link_id in (#{in_sql})", new_ids)
  .map { |row| row["start_link_id"].to_i }
unless clashing_ids.empty?
  raise "Ids already exist: #{clashing_ids}"
end

puts "Operations will be performed:"
type_operations.each do |operation|
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
  type = operation[0].rpartition("'")[0].rpartition["'"][2]
  result = db.exec_params(operation[0], operation[1])
  puts type
  result.check
end

failed_ids = []
id_operations.each do |operation|
  id = operation[1][0]
  result = db.exec_params(operation[0], operation[1])
  puts "#{id} #{result.cmd_status} #{result.cmd_tuples}"
  if result.cmd_tuples != 1
    failed_ids << id
  end
end

unless failed_ids.empty?
  raise "Insert failed for ids: #{failed_ids}"
end
