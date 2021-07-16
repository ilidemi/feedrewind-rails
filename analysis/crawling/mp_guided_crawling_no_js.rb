require_relative 'guided_crawling'
require_relative 'mp_common'

mp_run(GuidedCrawlRunnable.new, false, "guided_crawl")

