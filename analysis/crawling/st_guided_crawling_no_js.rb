require_relative 'run_guided_crawling'
require_relative 'st_common'

start_link_id = 456

runnable = GuidedCrawlRunnable.new
st_run(runnable, start_link_id, false)