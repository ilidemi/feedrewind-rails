require_relative '../db'

curl = "medium.com/@meduza"
start_link_id = 68
is_from_puppeteer = true
out_filename = "page.html"

db = connect_db
row = db.exec_params(
  "select content from mock_pages where canonical_url = $1 and start_link_id = $2 and is_from_puppeteer = $3",
  [curl, start_link_id, is_from_puppeteer]
).first
raise "Page not found" unless row

content = unescape_bytea(row["content"])
File.open(out_filename, "w") do |out_file|
  out_file.write(content)
end
