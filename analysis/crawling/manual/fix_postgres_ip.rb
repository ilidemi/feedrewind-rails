ip_output = %x[wsl ip addr]
ip = ip_output
  .split("\n")
  .filter_map { |line| /inet (172\.\d+\.\d+\.\d+)\/20/.match(line) }
  .first[1]
puts "IP #{ip}"

conf_path = "/etc/postgresql/12/main/postgresql.conf"
%x[wsl sudo sed -i "s/listen_addresses = '[0-9]\\+\\\\.[0-9]\\+\\\\.[0-9]\\+\\\\.[0-9]\\+'/listen_addresses = '#{ip}'/g" #{conf_path}]
conf_output = %x[wsl cat #{conf_path}]
conf_replaced_ip = /listen_addresses = '([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)'/.match(conf_output)[1]
puts "Conf IP: #{conf_replaced_ip}"

db_path = "db.rb"
%x[wsl sed -i "s/host: "\\""[0-9]\\+\\\\.[0-9]\\+\\\\.[0-9]\\+\\\\.[0-9]\\+"\\""/host: "\\""#{ip}"\\""/g" #{db_path}]
db_output = %x[wsl cat #{db_path}]
db_replaced_ip = /host: "(\d+\.\d+\.\d+\.\d+)"/.match(db_output)[1]
puts "DB IP: #{db_replaced_ip}"

data_sources_local_path = "../../.idea/dataSources.local.xml"
%x[wsl sed -i "s/rss_catchup_analysis@[0-9]\\+\\\\.[0-9]\\+\\\\.[0-9]\\+\\\\.[0-9]\\+/rss_catchup_analysis@#{ip}/g" #{data_sources_local_path}]
data_sources_local_output = %x[wsl cat #{data_sources_local_path}]
data_sources_local_replaced_ip = /rss_catchup_analysis@(\d+\.\d+\.\d+\.\d+)/.match(data_sources_local_output)[1]
puts "Data Sources local IP: #{data_sources_local_replaced_ip}"

data_sources_path = "../../.idea/dataSources.xml"
%x[wsl sed -i "s/rss_catchup_analysis@[0-9]\\+\\\\.[0-9]\\+\\\\.[0-9]\\+\\\\.[0-9]\\+/rss_catchup_analysis@#{ip}/g" #{data_sources_path}]
%x[wsl sed -i "s/[0-9]\\+\\\\.[0-9]\\+\\\\.[0-9]\\+\\\\.[0-9]\\+:5432\\/rss_catchup_analysis/#{ip}:5432\\/rss_catchup_analysis/g" #{data_sources_path}]
data_sources_output = %x[wsl cat #{data_sources_path}]
data_sources_replaced_ip1 = /rss_catchup_analysis@(\d+\.\d+\.\d+\.\d+)/.match(data_sources_output)[1]
data_sources_replaced_ip2 = /(\d+\.\d+\.\d+\.\d+):5432\/rss_catchup_analysis/.match(data_sources_output)[1]
puts "Data Sources IPs: #{data_sources_replaced_ip1} #{data_sources_replaced_ip2}"

database_yml_path = "../../config/database.yml"
%x[wsl sudo sed -i "s/host: [0-9]\\+\\\\.[0-9]\\+\\\\.[0-9]\\+\\\\.[0-9]\\+/host: #{ip}/g" #{database_yml_path}]
database_yml_output = %x[wsl cat #{database_yml_path}]
database_yml_replaced_ip = /host: (\d+\.\d+\.\d+\.\d+)/.match(database_yml_output)[1]
puts "database.yml IP: #{database_yml_replaced_ip}"

if conf_replaced_ip == ip
  puts %x[wsl sudo service postgresql start]
end
