require_relative 'guided_crawling'
require_relative 'st_common'

start_link_id = 406 # 105

runnable = GuidedCrawlRunnable.new
st_run(runnable, start_link_id, false)
