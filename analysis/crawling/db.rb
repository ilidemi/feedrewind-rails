require 'pg'

def connect_db
  PG.connect(host: "172.27.168.243", dbname: 'rss_catchup_analysis', user: "postgres")
end

def unescape_bytea(bytea)
  if bytea
    PG::Connection.unescape_bytea(bytea)
  else
    nil
  end
end