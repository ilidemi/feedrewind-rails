require_relative 'historical'
require_relative 'mp_common'

# require_relative 'db'
# db = connect_db
# archives_ids = db.exec("select start_link_id from historical_ground_truth where pattern in ('archives', 'archives_2xpaths') and start_link_id not in (select start_link_id from known_issues where severity = 'discard')").map { |row| row["start_link_id"].to_i }

mp_run(HistoricalRunnable.new, "historical", [1, 2, 3, 4, 6, 7, 8, 9, 10, 12, 13, 14, 15, 16, 17, 18, 19, 20, 22, 23])
