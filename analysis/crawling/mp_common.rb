require 'base64'
require 'fileutils'
require_relative 'crawling'
require_relative 'db'
require_relative 'logger'
require_relative 'report'
require_relative 'util'

MAX_PROCESS_COUNT = 3

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
  serialized = Base64.strict_decode64(safe_serialized[0...-1])
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

def mp_run(runnable, output_prefix, start_link_ids_override=nil)
  start_time = monotonic_now
  report_filename = "report/mp_#{output_prefix}_#{DateTime.now.strftime('%F_%H-%M-%S')}.html"
  db = connect_db
  if start_link_ids_override
    start_link_ids = start_link_ids_override
  else
    start_link_ids = db
      .exec("select id from start_links where id not in (select start_link_id from known_issues where severity = 'discard') order by id asc")
      .map { |row| row["id"].to_i }
  end
  process_count = [MAX_PROCESS_COUNT, start_link_ids.length].min
  id_queue = Queue.new
  start_link_ids.each do |id|
    id_queue << id
  end

  log_dir = "#{output_prefix}_log"
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
  id_writers = []
  running_readers = []
  result_readers = []
  process_count.times do
    id_reader, id_writer = IO.pipe
    id_writers << id_writer
    running_reader, running_writer = IO.pipe
    running_readers << running_reader
    result_reader, result_writer = IO.pipe
    result_readers << result_reader

    pid = fork do
      trap("TERM", "EXIT")
      trap("PIPE", "EXIT")
      id_writer.close
      running_reader.close
      result_reader.close
      process_db = connect_db

      loop do
        start_link_id = id_reader.gets.to_i
        running_writer.puts(start_link_id)
        begin
          File.open("#{log_dir}/log#{start_link_id}.txt", 'a') do |log_file|
            logger = MyLogger.new(log_file)
            result = runnable.run(start_link_id, true, process_db, logger)
            write_object(result_writer, [start_link_id, result, nil])
          end
        rescue => error
          File.open("#{log_dir}/exception#{start_link_id}.txt", 'w') do |error_file|
            print_nice_error(error_file, error)
          end
          result = error.is_a?(RunError) ? error.result : nil
          write_object(result_writer, [start_link_id, result, error.message])
        end
      end
    end

    pids << pid
    id_reader.close
    running_writer.close
    result_writer.close
  end

  processes_finished = []
  trap("INT") do
    kill_all_processes(pids, processes_finished)
    puts "Interrupted"
    exit
  end

  id_writers.each do |id_writer|
    id_writer.puts(id_queue.deq)
  end

  ids_running = [nil] * process_count
  processes_running = process_count
  results = []
  iteration = 0
  loop do
    sleep(0.1)

    running_readers.each_with_index do |running_reader, i|
      next if processes_finished.include?(i)
      next unless has_data_to_read(running_reader)
      running_id = running_reader.gets.to_i
      ids_running[i] = running_id
    end

    result_readers.each_with_index do |result_reader, i|
      next if processes_finished.include?(i)
      next unless has_data_to_read(result_reader)
      result = read_object(result_reader)
      if result.nil?
        puts "Read nil instead of object from process #{i}. It's probably dead."
        kill_all_processes(pids, processes_finished)
        puts "Aborted"
        exit
      end
      results << result

      if id_queue.empty?
        Process.kill(:KILL, pids[i])
        processes_running -= 1
        processes_finished << i
        ids_running[i] = nil
      else
        id_writers[i].puts(id_queue.deq)
      end
    end

    if iteration % 10 == 0
      output_report(report_filename, runnable.result_column_names, results, start_link_ids.length)
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

      puts "#{Time.now.strftime('%F %T')} elapsed:#{elapsed_str} total:#{start_link_ids.length} to_dispatch:#{id_queue.length} to_process:#{start_link_ids.length - results.length} running:#{processes_running} #{ids_running}#{memory_log}"
    end

    iteration += 1
    break if results.length == start_link_ids.length
  end

  output_report(report_filename, runnable.result_column_names, results, start_link_ids.length)
end