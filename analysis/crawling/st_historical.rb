require_relative 'historical'
require_relative 'st_common'

start_link_id = 8

runnable = HistoricalRunnable.new
st_run(runnable, start_link_id)
