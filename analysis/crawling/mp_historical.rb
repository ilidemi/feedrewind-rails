require_relative 'discover_historical_entries'
require_relative 'mp_common'

mp_run(HistoricalRunnable.new, "historical")
