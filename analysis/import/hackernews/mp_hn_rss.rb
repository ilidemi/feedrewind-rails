require 'base64'
require 'csv'
require 'fileutils'
require 'set'
require 'sqlite3'
require_relative '../../crawling/logger'
require_relative '../../../app/lib/guided_crawling/util'
require_relative 'hn_rss'

MAX_PROCESS_COUNT = 16
score_cutoff = 10
batch_size = 1

def has_data_to_read(io)
  select_result = IO.select([io], nil, nil, 0)
  select_result && select_result[0][0] == io
end

def write_object(io, object)
  serialized = Marshal.dump(object)
  safe_serialized = Base64.strict_encode64(serialized)
  io.puts(safe_serialized)
end

def read_object(io)
  safe_serialized = io.gets
  return nil if safe_serialized.nil?
  serialized = Base64.strict_decode64(safe_serialized[...-1])
  Marshal.load(serialized)
end

def kill_all_processes(pids, processes_finished)
  puts "Shutting down processes"
  pids.each_with_index do |pid, i|
    next if processes_finished.include?(i)
    begin
      Process.kill(:KILL, pid)
    rescue => e
      puts "Couldn't kill process #{pid}: #{e}"
    end
  end
end

start_time = monotonic_now
logger = MyLogger.new($stdout)

urls_csv = CSV.read('xps15.csv')[1..]
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

input_row_queue = Queue.new
index = 0
top_urls_csv.each do |url, sum_score, count|
  index += 1
  if indices_processed.include?(index)
    logger.info("#{index}/#{top_urls_csv.length} Url #{url}, sum_score #{sum_score}, count #{count}")
    logger.info("Url already processed")
    next
  end

  input_row_queue << InputRow.new(index, url, sum_score.to_i, count.to_i)
end

input_rows_count = input_row_queue.length
process_count = [MAX_PROCESS_COUNT, input_rows_count].min

log_dir = "log"
unless File.exist?(log_dir)
  FileUtils.mkdir(log_dir)
end
Dir.new(log_dir).each_child do |filename|
  File.delete("#{log_dir}/#{filename}")
end

begin
  `free`
  is_free_available = true
rescue Errno::ENOENT
  is_free_available = false
end

pids = []
input_row_writers = []
running_readers = []
result_readers = []
process_count.times do |process_idx|
  input_row_reader, input_row_writer = IO.pipe
  input_row_writers << input_row_writer
  running_reader, running_writer = IO.pipe
  running_readers << running_reader
  result_reader, result_writer = IO.pipe
  result_readers << result_reader

  pid = fork do
    trap("TERM", "EXIT")
    trap("PIPE", "EXIT")
    input_row_writer.close
    running_reader.close
    result_reader.close

    File.open("#{log_dir}/log#{process_idx}.txt", 'a') do |log_file|
      logger = MyLogger.new(log_file)
      throttler = Throttler.new

      loop do
        input_rows = read_object(input_row_reader)
        running_writer.puts(input_rows.map(&:index).min)
        begin
          result = hn_rss(input_rows, throttler, logger)
          write_object(result_writer, result)
        rescue => e
          logger.write("--- EXCEPTION ---")
          error_lines = print_nice_error(e)
          error_lines.each do |line|
            log_file.puts(line)
          end
        end
      end
    end
  end

  pids << pid
  input_row_reader.close
  running_writer.close
  result_writer.close
end

processes_finished = []
trap("INT") do
  kill_all_processes(pids, processes_finished)
  puts "Interrupted"
  exit
end

process_input_row_queues = process_count.times.map { Queue.new }
process_idxs_by_host = {}

def get_next_input_batch(
  process_idx, batch_size, input_row_queue, process_input_row_queues, process_idxs_by_host
)
  input_rows = []
  batch_size.times do
    input_row = get_next_input(process_idx, input_row_queue, process_input_row_queues, process_idxs_by_host)
    return input_rows unless input_row

    input_rows << input_row
  end

  input_rows
end

def get_next_input(process_idx, input_row_queue, process_input_row_queues, process_idxs_by_host)
  unless process_input_row_queues[process_idx].empty?
    return process_input_row_queues[process_idx].deq
  end

  until input_row_queue.empty?
    input_row = input_row_queue.deq
    begin
      uri = URI(input_row.url)
    rescue
      next
    end
    if process_idxs_by_host.key?(uri.host)
      host_process_idx = process_idxs_by_host[uri.host]
      if host_process_idx == process_idx
        return input_row
      end

      process_input_row_queues[process_idx] << input_row
    else
      process_idxs_by_host[uri.host] = process_idx
      return input_row
    end
  end

  nil
end

input_row_writers.each_with_index do |input_row_writer, process_idx|
  input_rows = get_next_input_batch(
    process_idx, batch_size, input_row_queue, process_input_row_queues, process_idxs_by_host
  )
  write_object(input_row_writer, input_rows)
end

indices_running = [nil] * process_count
processes_running = process_count
results_count = 0
iteration = 0
loop do
  sleep(0.1)

  running_readers.each_with_index do |running_reader, process_idx|
    next if processes_finished.include?(process_idx)
    next unless has_data_to_read(running_reader)
    running_index = running_reader.gets.to_i
    indices_running[process_idx] = running_index
  end

  results_batch = []
  result_readers.each_with_index do |result_reader, process_idx|
    next if processes_finished.include?(process_idx)
    next unless has_data_to_read(result_reader)
    result = read_object(result_reader)
    if result.nil?
      puts "Read nil instead of object from process #{process_idx}. It's probably dead."
      processes_finished << process_idx
      next
      # kill_all_processes(pids, processes_finished)
      # puts "Aborted"
      # exit
    end
    results_batch << result

    input_rows = get_next_input_batch(
      process_idx, batch_size, input_row_queue, process_input_row_queues, process_idxs_by_host
    )

    if !input_rows.empty?
      write_object(input_row_writers[process_idx], input_rows)
    else
      Process.kill(:KILL, pids[process_idx])
      processes_running -= 1
      processes_finished << process_idx
      indices_running[process_idx] = nil
    end
  end

  results_batch.each do |result|
    feeds, scores, redirects, rows_processed, errors = result
    results_count += rows_processed.length + errors.length

    db.transaction
    feeds.each do |url, feed_url|
      db.execute(
        "insert into feeds (url, feed_url) values (?, ?)",
        [url, feed_url]
      )
    end
    scores.each do |url, sum_score, count|
      db.execute(
        "insert into scores (url, sum_score, count) values (?, ?, ?)",
        [url, sum_score, count]
      )
    end
    redirects.each do |curl, url|
      db.execute(
        "insert into redirects (prefix_curl, url) values (?, ?)",
        [curl, url]
      )
    end
    rows_processed.each do |index|
      db.execute("insert into rows_processed (row) values (?)", [index])
    end
    db.commit
  end

  if iteration % 10 == 0
    current_time = monotonic_now
    elapsed_seconds = (current_time - start_time).to_i
    if elapsed_seconds < 60
      elapsed_str = "%ds" % elapsed_seconds
    elsif elapsed_seconds < 3600
      elapsed_str = "%dm%02ds" % [elapsed_seconds / 60, elapsed_seconds % 60]
    else
      elapsed_str = "%dh%02dm%02ds" % [
        elapsed_seconds / 3600,
        (elapsed_seconds % 3600) / 60,
        elapsed_seconds % 60
      ]
    end

    if is_free_available
      free_output = `free -m`
      memory_tokens = free_output.split("\n")[1].split(" ")
      memory_log = " memory total:#{memory_tokens[1]} used:#{memory_tokens[2]} shared:#{memory_tokens[4]} cache:#{memory_tokens[5]} free:#{memory_tokens[3]}"
    else
      memory_log = ''
    end

    max_process_queue_length = process_input_row_queues.map(&:length).max

    puts "#{Time.now.strftime('%F %T')} elapsed:#{elapsed_str} total:#{input_rows_count} to_dispatch:#{input_row_queue.length} to_process:#{input_rows_count - results_count} running:#{processes_running} done:#{results_count} skew:#{max_process_queue_length} idxs:#{indices_running}#{memory_log}"
  end

  iteration += 1
  break if results_count == input_rows_count
end