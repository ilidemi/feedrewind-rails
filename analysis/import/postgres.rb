require 'sqlite3'
require 'pg'

sl_db = SQLite3::Database.new('blogs.db')
pg_db = PG.connect(host: "localhost", dbname: 'rss_catchup_analysis', user: "postgres")

# sl_db.execute('select * from sources') do |row|
#   print row
#   pg_db.exec_params("insert into sources (id, name) values ($1, $2)", [row[0], row[1]])
# end

# sl_db.execute('select * from start_links') do |row|
#   print row
#   pg_db.exec_params('insert into start_links (source_id, url, comment) values ($1, $2, $3)', [row[1], row[2], row[3]])
# end
