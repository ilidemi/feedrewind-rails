require 'fileutils'
require_relative 'crawling'
require_relative 'db'
require_relative 'logger'
require_relative 'report'

report_filename = "report/mt_report_#{DateTime.now.strftime('%F_%H-%M-%S')}.html"
db = db_connect
start_link_ids = db.exec('select id from start_links').map { |row| row["id"].to_i }
id_queue = Queue.new
start_link_ids.each do |id|
  id_queue << id
end

unless File.exist?("log")
  FileUtils.mkdir("log")
end
Dir.new("log").each_child do |filename|
  File.delete("log/#{filename}")
end

result_queue = Queue.new

thread_count = 16
threads = []
thread_count.times do
  thread = Thread.new do
    thread_db = db_connect
    until id_queue.empty? do
      begin
        start_link_id = id_queue.deq(non_block = true)
      rescue ThreadError
        break # End of queue
      end

      begin
        File.open("log/log#{start_link_id}.txt", 'a') do |log_file|
          logger = MyLogger.new(log_file)
          result = discover_feed(thread_db, start_link_id, logger)
          result_queue << [start_link_id, result, nil]
        end
      rescue => error
        File.open("log/exception#{start_link_id}.txt", 'w') do |error_file|
          error_file.write("#{error.to_s}\n#{error.backtrace}")
        end
        result = error.is_a?(CrawlingError) ? error.result : nil
        result_queue << [start_link_id, result, error.message]
      end
    end
  end
  threads << thread
end

status_names = {
  "sleep" => "running",
  "run" => "running",
  nil => "exception",
  false => "finished"
}

results = []
loop do
  sleep(1)
  statuses = Hash.new(0)
  threads.each do |thread|
    if status_names.key?(thread.status)
      statuses[status_names[thread.status]] += 1
    else
      statuses[thread.status] += 1
    end
  end

  until result_queue.empty?
    results << result_queue.deq
  end

  output_report(report_filename, results, start_link_ids.length)

  puts "Queue size: #{id_queue.length}, Thread statuses: #{statuses}"

  break if (statuses['exception'] + statuses['finished']) == thread_count
end
