require 'pg'
require_relative 'crawling'

def db_connect
  PG.connect(host: "172.18.67.31", dbname: 'rss_catchup_analysis', user: "postgres")
end

db = db_connect
start_link_ids = db.exec('select id from start_links').map { |row| row["id"] }
id_queue = Queue.new
start_link_ids.each do |id|
  id_queue << id
end

thread_count = 96
threads = []
thread_count.times do
  thread = Thread.new do
    thread_db = db_connect
    until id_queue.empty? do
      begin
        start_link_id = id_queue.deq(non_block=true)
        File.open("log/log#{start_link_id}.txt", 'a') do |log_file|
          start_crawl(thread_db, start_link_id, log_file)
        end
      rescue ThreadError
        # End of queue
      rescue => error
        File.open("log/exception#{start_link_id}.txt", 'w') do |error_file|
          error_file.write("#{error.to_s}\n#{error.backtrace}")
        end
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

  puts "Queue size: #{id_queue.length}, Thread statuses: #{statuses}"

  break if (statuses['exception'] + statuses['finished']) == thread_count
end
