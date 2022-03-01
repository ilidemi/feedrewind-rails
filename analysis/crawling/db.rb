require 'pg'

def connect_db
  PG.connect(host: "172.17.78.86", dbname: 'rss_catchup_analysis', user: "postgres")
end

def unescape_bytea(bytea)
  if bytea
    PG::Connection.unescape_bytea(bytea)
  else
    nil
  end
end