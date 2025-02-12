ip_output = %x[wsl ip addr]
ip = ip_output
  .split("\n")
  .filter_map { |line| /inet ((172\.\d+|192\.168)\.\d+\.\d+)\/20/.match(line) }
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

database_yml_path = "../../config/database.yml"
%x[wsl sudo sed -i "s/host: [0-9]\\+\\\\.[0-9]\\+\\\\.[0-9]\\+\\\\.[0-9]\\+/host: #{ip}/g" #{database_yml_path}]
database_yml_output = %x[wsl cat #{database_yml_path}]
database_yml_replaced_ip = /host: (\d+\.\d+\.\d+\.\d+)/.match(database_yml_output)[1]
puts "database.yml IP: #{database_yml_replaced_ip}"

dbnavigator_xml_path = "../../.idea/dbnavigator.xml"
%x[wsl sudo sed -i "s/<host value=\\"[0-9]+\\\\.[0-9]+\\\\.[0-9]+\\\\.[0-9]+\\" \\/>/<host value=\\"#{ip}\\" \\/>/g" #{dbnavigator_xml_path}]
dbnavigator_xml_output = %x[wsl cat #{dbnavigator_xml_path}]
dbnavigator_xml_replaced_ip = /<host value="\d+.\d+.\d+.\d+" \/>/.match(dbnavigator_xml_output)[1]
puts "dbnavigator.xml IP: #{dbnavigator_xml_replaced_ip}"

if conf_replaced_ip == ip
  puts %x[wsl sudo service postgresql start]
end

puts %x[wsl sudo screen -S tailscale -dm tailscaled]
