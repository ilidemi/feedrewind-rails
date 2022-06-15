require 'json'
require 'tzinfo'
require 'set'

# From https://github.com/vvo/tzdb/blob/main/raw-time-zones.json
File.open("raw-time-zones.json") do |file|
  json = JSON.parse(file.read)

  name_overrides = {
    "Pacific/Kanton" => "Pacific/Enderbury", # Pacific/Kanton is not in tzinfo
  }
  friendly_name_overrides = {
    "Pacific/Kanton" => "+13:00 Phoenix Islands Time - Endenbury", # Pacific/Kanton is not in tzinfo
  }

  tzdb_groups = Set.new
  puts "FRIENDLY_NAME_BY_GROUP_ID = {"
  json.each do |row|
    name = name_overrides.include?(row["name"]) ? name_overrides[row["name"]] : row["name"]
    tzdb_groups << name
    friendly_name = friendly_name_overrides.include?(row["name"]) ? friendly_name_overrides[row["name"]] : row["rawFormat"]
    puts "\"#{name}\" => \"#{friendly_name}\","
  end
  puts "}"

  tzdb_timezones = Set.new
  puts "GROUP_ID_BY_TIMEZONE_ID = {"
  json.each do |row|
    row["group"].each do |timezone|
      next if tzdb_timezones.include?(timezone)
      tzdb_timezones << timezone
      name = name_overrides.include?(row["name"]) ? name_overrides[row["name"]] : row["name"]
      puts "\"#{timezone}\" => \"#{name}\","
    end
  end
  puts "}"

  TZInfo::Timezone.all_country_zone_identifiers.each do |timezone|
    unless tzdb_timezones.include?(timezone)
      puts "WARNING: #{timezone} from tzinfo is not in tzdb"
    end
  end

  tzinfo_all_timezones = TZInfo::Timezone.all_identifiers.to_set
  tzdb_groups.each do |timezone|
    unless tzinfo_all_timezones.include?(timezone)
      puts "WARNING: #{timezone} group from tzdb is not in tzinfo"
    end
  end
end
