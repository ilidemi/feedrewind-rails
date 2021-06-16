require_relative 'crawling'
require_relative 'mp_common'

raise "DB has some nicely crawled stuff right now!"

mp_run(CrawlRunnable.new, "crawl")
