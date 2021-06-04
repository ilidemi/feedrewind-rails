require 'set'
require_relative 'db'

db = connect_db
query_uris = db
  .exec("select fetch_url, start_link_id from pages where fetch_url like '%?%'")
  .map { |row| { uri: URI(row["fetch_url"]), start_link_id: row["start_link_id"].to_i } }
puts "Uris with query: #{query_uris.length}"

uris_by_param = {}
start_link_ids_by_param = {}
values_by_param = {}
duplicate_param_uris = Set.new

query_uris.each do |uri|
  query_list = uri[:uri]
    .query
    .split("&")
    .map { |kv| kv.split("=") }

  if query_list.uniq { |key, _| key }.length != query_list.length
    duplicate_param_uris << uri
  end

  query = query_list.to_h { |k, v| [k, v] }
  query.each do |k, v|
    unless uris_by_param.key?(k)
      uris_by_param[k] = Set.new
    end
    uris_by_param[k] << uri[:uri]

    unless start_link_ids_by_param.key?(k)
      start_link_ids_by_param[k] = Set.new
    end
    start_link_ids_by_param[k] << uri[:start_link_id]

    unless values_by_param.key?(k)
      values_by_param[k] = Set.new
    end
    values_by_param[k] << v
  end
end

puts "Unique params: #{uris_by_param.length}"
param_with_most_uris = uris_by_param.max_by { |_, v| v.length }
puts "Most uris by param: #{param_with_most_uris[0]} (#{param_with_most_uris[1].length})"
param_with_most_start_link_ids = start_link_ids_by_param.max_by { |_, v| v.length }
puts "Most start links ids by param: #{param_with_most_start_link_ids[0]} (#{param_with_most_start_link_ids[1].length})"
param_with_most_values = values_by_param.max_by { |_, v| v.length }
puts "Most values by param: #{param_with_most_values[0]} (#{param_with_most_values[1].length})"

puts "Done"