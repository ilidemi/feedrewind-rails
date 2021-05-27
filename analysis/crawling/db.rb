require 'pg'

def db_connect
  PG.connect(host: "172.18.67.31", dbname: 'rss_catchup_analysis', user: "postgres")
end
