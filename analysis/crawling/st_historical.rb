require_relative 'discover_historical_entries'
require_relative 'st_common'

start_link_id = 127

runnable = HistoricalRunnable.new
st_run(runnable, start_link_id)
