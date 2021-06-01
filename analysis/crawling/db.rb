require 'pg'

def db_connect
  PG.connect(host: "172.19.90.91", dbname: 'rss_catchup_analysis', user: "postgres")
end
