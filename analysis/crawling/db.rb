require 'pg'

def connect_db
  PG.connect(host: "172.30.124.11", dbname: 'rss_catchup_analysis', user: "postgres")
end

def unescape_bytea(bytea)
  if bytea
    PG::Connection.unescape_bytea(bytea)
  else
    nil
  end
end