require_relative 'crawling'
require_relative 'st_common'

# raise "There is a lot of useful stuff in db, pls no wipe"

start_link_id = 239

runnable = CrawlRunnable.new
st_run(runnable, start_link_id)

