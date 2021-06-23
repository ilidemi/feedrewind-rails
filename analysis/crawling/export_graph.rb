require_relative 'db'
require_relative 'structs'

def export_graph(db, start_link_id, start_link, allowed_hosts, feed_uri, feed_urls, logger)
  logger.log("Export graph started")
  redirects = db
    .exec_params(
      'select from_fetch_url, to_fetch_url from redirects where start_link_id = $1',
      [start_link_id]
    )
    .to_h do |row|
    [row["from_fetch_url"], to_canonical_link(row["to_fetch_url"], logger)]
  end

  pages = db
    .exec_params(
      'select canonical_url, fetch_url, content_type, content from pages where start_link_id = $1',
      [start_link_id]
    )
    .to_h { |row| [row["canonical_url"], Page.new(row["canonical_url"], URI(row["fetch_url"]), row["content_type"], unescape_bytea(row["content"]))] }
    .filter { |_, page| !page.content.nil? }

  def to_node_label(canonical_url, allowed_hosts)
    if allowed_hosts.length == 1
      "/" + canonical_url.partition("/")[2]
    else
      canonical_url
    end
  end

  def feed_url_to_node_label(feed_url, allowed_hosts, redirects, fetch_uri, logger)
    feed_link = to_canonical_link(feed_url, logger, fetch_uri)
    redirected_link = follow_cached_redirects(feed_link, redirects)
    to_node_label(redirected_link.canonical_url, allowed_hosts)
  end

  root_label = feed_url_to_node_label(feed_urls.root_url, allowed_hosts, redirects, feed_uri, logger)
  item_label_to_index = feed_urls
    .item_urls
    .map.with_index { |url, index| [feed_url_to_node_label(url, allowed_hosts, redirects, feed_uri, logger), index] }
    .to_h

  graph = pages.to_h do |canonical_url, page|
    [
      to_node_label(canonical_url, allowed_hosts),
      extract_links(page, allowed_hosts, redirects, logger)
        .filter { |link| pages.key?(link.canonical_url) }
        .map { |link| to_node_label(link.canonical_url, allowed_hosts) }
    ]
  end

  start_link_label = to_node_label(start_link.canonical_url, allowed_hosts)

  File.open("graph/#{start_link_id}.dot", "w") do |dot_f|
    dot_f.write("digraph G {\n")
    dot_f.write("    graph [overlap=false outputorder=edgesfirst]\n")
    dot_f.write("    node [style=filled fillcolor=white]\n")
    graph.each_key do |node|
      attributes = { "shape" => "box" }
      if node == start_link_label && node == root_label
        attributes["fillcolor"] = "orange"
      elsif node == start_link_label
        attributes["fillcolor"] = "yellow"
      elsif node == root_label
        attributes["fillcolor"] = "red"
      elsif item_label_to_index.key?(node)
        if item_label_to_index.length > 1
          spectrum_pos = item_label_to_index[node].to_f / (item_label_to_index.length - 1)
          green = (128 + (1.0 - spectrum_pos) * 127).to_i.to_s(16)
          blue = (128 + spectrum_pos * 127).to_i.to_s(16)
        else
          green = "ff"
          blue = "00"
        end
        attributes["fillcolor"] = "\"\#80#{green}#{blue}\""
      end
      attributes_str = attributes
        .map { |k, v| "#{k}=#{v}" }
        .to_a
        .join(", ")
      dot_f.write("    \"#{node}\" [#{attributes_str}]\n")
    end
    graph.each do |node1, node2s|
      filtered_node2s = item_label_to_index.key?(node1) ?
        node2s.filter { |node2| item_label_to_index.key?(node2) } :
        node2s
      filtered_node2s.each do |node2|
        dot_f.write("    \"#{node1}\" -> \"#{node2}\"\n")
      end
    end
    dot_f.write("}\n")
  end
  logger.log("Export graph finished")
end
