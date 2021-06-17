require_relative 'discover_historical_entries'
require_relative 'mp_common'

# require_relative 'db'
# db = connect_db
# archives_ids = db.exec("select start_link_id from historical_ground_truth where pattern in ('archives', 'archives_2xpaths') and start_link_id not in (select start_link_id from known_failures)").map { |row| row["start_link_id"].to_i }

mp_run(HistoricalRunnable.new, "historical")
