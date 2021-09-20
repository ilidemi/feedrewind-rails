require_relative 'run_guided_crawling'
require_relative 'mp_common'

mp_run(GuidedCrawlRunnable.new, false, "guided_crawl")

