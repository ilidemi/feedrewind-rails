require 'set'
require_relative 'crawling'
require_relative 'feed_parsing'
require_relative 'run_common'
require_relative 'util'

HISTORICAL_RESULT_COLUMNS = [
  [:start_url, :neutral],
  [:comment, :neutral],
  [:gt_pattern, :neutral],
  [:feed_links, :boolean],
  [:found_items_count, :neutral_present],
  [:all_items_found, :boolean],
  [:historical_links_matching, :boolean],
  [:historical_links_pattern, :neutral_present],
  [:historical_links_count, :neutral_present],
  [:main_url, :neutral_present],
  [:oldest_link, :neutral_present],
  [:total_time, :neutral]
]

class HistoricalRunnable
  def initialize
    @result_column_names = to_column_names(HISTORICAL_RESULT_COLUMNS)
  end

  def run(start_link_id, db, logger)
    discover_historical_entries_from_scratch(start_link_id, db, logger)
  end

  attr_reader :result_column_names
end

def discover_historical_entries_from_scratch(start_link_id, db, logger)
  logger.log("Discover historical entries from scratch started")

  start_link_url = db.exec_params('select url from start_links where id = $1', [start_link_id])[0]["url"]
  result = RunResult.new(HISTORICAL_RESULT_COLUMNS)
  result.start_url = "<a href=\"#{start_link_url}\">#{start_link_url}</a>"
  start_time = monotonic_now

  begin
    comment_row = db.exec_params(
      'select comment from crawler_comments where start_link_id = $1',
      [start_link_id]
    ).first
    if comment_row
      result.comment = comment_row["comment"]
    end

    gt_row = db.exec_params(
      "select pattern, entries_count, main_page_canonical_url, oldest_entry_canonical_url from historical_ground_truth where start_link_id = $1",
      [start_link_id]
    ).first
    if gt_row
      result.gt_pattern = gt_row["pattern"]
    end

    redirects = db.exec_params(
      "select from_fetch_url, to_fetch_url from redirects where start_link_id = $1",
      [start_link_id]
    ).to_h do |row|
      [row["from_fetch_url"], to_canonical_link(row["to_fetch_url"], logger, URI(row["from_fetch_url"]))]
    end

    feed_row = db.exec_params(
      "select content, fetch_url from pages where id in (select page_id from feeds where start_link_id = $1)",
      [start_link_id]
    ).first
    raise "Feed not found in db" unless feed_row

    feed_page = { content: unescape_bytea(feed_row["content"]), fetch_uri: URI(feed_row["fetch_url"]) }
    feed_urls = extract_feed_urls(feed_page[:content], logger)
    item_links = feed_urls
      .item_urls
      .map { |url| to_canonical_link(url, logger, feed_page[:fetch_uri]) }
      .map { |link| follow_cached_redirects(link, redirects) }
    item_canonical_urls = item_links.map { |link| link[:canonical_url] }
    allowed_hosts = item_links
      .map { |link| link[:host] }
      .to_set

    result.feed_links = item_links.length
    found_items_placeholders = item_canonical_urls.map.with_index(2) { |_, i| "$#{i}::TEXT" }.join(', ')
    found_items_count = db.exec_params(
      "select count(*) from pages where content is not null and start_link_id = $1 and canonical_url in (#{found_items_placeholders})",
      [start_link_id] + item_canonical_urls
    ).first["count"].to_i
    logger.log("Found feed links: #{found_items_count}")
    result.found_items_count = found_items_count
    all_items_found = found_items_count == item_canonical_urls.length
    result.all_items_found = all_items_found
    raise "Not all items found" unless all_items_found

    historical_links = discover_historical_entries(
      start_link_id, item_canonical_urls, allowed_hosts, redirects, db, logger
    )

    raise "Historical links not found" if historical_links.nil?

    entries_count = historical_links[:links].length
    oldest_link = historical_links[:links][-1]

    if gt_row
      historical_links_matching = true
      if historical_links[:pattern] == gt_row["pattern"]
        result.historical_links_pattern_status = :success
        result.historical_links_pattern = historical_links[:pattern]
      else
        result.historical_links_pattern_status = :failure
        result.historical_links_pattern = "#{historical_links[:pattern]} (#{gt_row["pattern"]})"
        historical_links_matching = false
      end

      gt_entries_count = gt_row["entries_count"].to_i
      if gt_entries_count == entries_count
        result.historical_links_count_status = :success
        result.historical_links_count = entries_count
      else
        historical_links_matching = false
        result.historical_links_count_status = :failure
        result.historical_links_count = "#{entries_count} (#{gt_entries_count})"
      end

      # TODO: Skipping the check for the main page url for now

      gt_oldest_canonical_url = gt_row["oldest_entry_canonical_url"]
      if gt_oldest_canonical_url == oldest_link[:canonical_url]
        result.oldest_link_status = :success
        result.oldest_link = "<a href=\"#{oldest_link[:url]}\">#{oldest_link[:canonical_url]}</a>"
      else
        historical_links_matching = false
        result.oldest_link_status = :failure
        result.oldest_link = "<a href=\"#{oldest_link[:url]}\">#{oldest_link[:canonical_url]}</a><br>(#{gt_oldest_canonical_url})"
      end

      result.historical_links_matching = historical_links_matching
    else
      result.historical_links_matching = '?'
      result.historical_links_matching_status = :neutral
      result.historical_links_pattern = historical_links[:pattern]
      result.historical_links_count = entries_count
      result.oldest_link = "<a href=\"#{oldest_link[:url]}\">#{oldest_link[:canonical_url]}</a>"
    end

    result.main_url = "<a href=\"#{historical_links[:main_fetch_url]}\">#{historical_links[:main_canonical_url]}</a>"

    logger.log("Discover historical entries from scratch finished")
    result
  rescue => e
    raise RunError.new(e.message, result), e
  ensure
    result.total_time = (monotonic_now - start_time).to_i
  end
end

def discover_historical_entries(start_link_id, feed_item_urls, allowed_hosts, redirects, db, logger)
  logger.log("Discover historical entries started")

  db.transaction do |transaction|
    transaction.exec_params(
      "declare pages_cursor cursor for select canonical_url, fetch_url, content_type, content from pages where start_link_id = $1 and content is not null order by length(canonical_url) asc",
      [start_link_id]
    )

    feed_item_urls_set = feed_item_urls.to_set

    loop do
      rows = transaction.exec("fetch next from pages_cursor")
      if rows.cmd_tuples == 0
        break
      end

      row = rows[0]
      page = { canonical_url: row["canonical_url"], fetch_uri: URI(row["fetch_url"]), content_type: row["content_type"], content: unescape_bytea(row["content"]) }
      page_links = extract_links(page, allowed_hosts, redirects, logger, include_xpath = true)
      allowed_urls = page_links[:allowed_host_links]
        .map { |link| link[:canonical_url] }
        .to_set
      if feed_item_urls.all? { |item_url| allowed_urls.include?(item_url) }
        logger.log("Possible archives page: #{page[:canonical_url]}")

        logger.log("Trying xpaths with a single star")
        historical_links = try_masked_xpaths(
          page_links, feed_item_urls, feed_item_urls_set, :get_single_masked_xpaths,
          logger
        )

        unless historical_links
          logger.log("Trying xpaths with two stars")
          historical_links = try_masked_xpaths(
            page_links, feed_item_urls, feed_item_urls_set, :get_double_masked_xpaths,
            logger
          )
        end

        unless historical_links
          logger.log("Trying xpaths with three stars")
          historical_links = try_masked_xpaths(
            page_links, feed_item_urls, feed_item_urls_set, :get_triple_masked_xpaths,
            logger
          )
        end

        if historical_links
          return { main_canonical_url: page[:canonical_url], main_fetch_url: page[:fetch_uri].to_s, links: historical_links[:links], pattern: historical_links[:pattern] }
        end

        logger.log("Not an archives page")
      end
    end
  end

  nil
end

def try_masked_xpaths(page_links, feed_item_urls, feed_item_urls_set, get_masked_xpaths_name, logger)
  get_masked_xpaths_func = method(get_masked_xpaths_name)
  links_by_masked_xpath = {}
  page_feed_links, page_non_feed_links = page_links[:allowed_host_links]
    .partition { |page_link| feed_item_urls_set.include?(page_link[:canonical_url]) }
  page_feed_links.each do |page_feed_link|
    masked_xpaths = get_masked_xpaths_func.call(page_feed_link[:xpath])
    masked_xpaths.each do |masked_xpath|
      unless links_by_masked_xpath.key?(masked_xpath)
        links_by_masked_xpath[masked_xpath] = []
      end
      links_by_masked_xpath[masked_xpath] << page_feed_link
    end
  end
  page_non_feed_links.each do |page_non_feed_link|
    masked_xpaths = get_masked_xpaths_func.call(page_non_feed_link[:xpath])
    masked_xpaths.each do |masked_xpath|
      next unless links_by_masked_xpath.key?(masked_xpath)
      links_by_masked_xpath[masked_xpath] << page_non_feed_link
    end
  end
  logger.log("Masked xpaths: #{links_by_masked_xpath.length}")

  # Collapse consecutive duplicates: [a, b, b, c] -> [a, b, c] but [a, b, c, b] -> [a, b, c, b]
  collapsed_links_by_masked_xpath = links_by_masked_xpath.to_h do |masked_xpath, masked_xpath_links|
    collapsed_links = []
    masked_xpath_links.length.times do |index|
      if index == 0 || masked_xpath_links[index][:canonical_url] != masked_xpath_links[index - 1][:canonical_url]
        collapsed_links << masked_xpath_links[index]
      end
    end
    [masked_xpath, collapsed_links]
  end

  collapsed_links_by_masked_xpath.each do |masked_xpath, masked_xpath_links|
    next if masked_xpath_links.length < feed_item_urls.length

    masked_xpath_link_urls = masked_xpath_links.map { |link| link[:canonical_url] }
    masked_xpath_link_urls_set = masked_xpath_link_urls.to_set
    next unless feed_item_urls.all? { |item_url| masked_xpath_link_urls_set.include?(item_url) }

    if masked_xpath_link_urls_set.length != masked_xpath_link_urls.length
      logger.log("Masked xpath #{masked_xpath} has all links but also duplicates: #{masked_xpath_link_urls}")
      next
    end

    if feed_item_urls == masked_xpath_link_urls[0...feed_item_urls.length]
      collapsion_log_str = get_collapsion_log_str(masked_xpath, links_by_masked_xpath, collapsed_links_by_masked_xpath)
      logger.log("Masked xpath is good: #{masked_xpath}#{collapsion_log_str}")
      return { pattern: "archives", links: masked_xpath_links }
    end

    reversed_masked_xpath_links = masked_xpath_links.reverse
    reversed_masked_xpath_link_urls = masked_xpath_link_urls.reverse
    if feed_item_urls == reversed_masked_xpath_link_urls[0...feed_item_urls.length]
      collapsion_log_str = get_collapsion_log_str(masked_xpath, links_by_masked_xpath, collapsed_links_by_masked_xpath)
      logger.log("Masked xpath is good in reverse order: #{masked_xpath}#{collapsion_log_str}")
      return { pattern: "archives", links: reversed_masked_xpath_links }
    end

    logger.log("Masked xpath #{masked_xpath} has all links #{feed_item_urls} but not in the right order: #{masked_xpath_link_urls}")
  end

  feed_prefix_xpaths_by_length = {}
  collapsed_links_by_masked_xpath.each do |masked_xpath, masked_xpath_links|
    next if masked_xpath_links.length >= feed_item_urls.length

    feed_item_urls.zip(masked_xpath_links).each_with_index do |pair, index|
      feed_item_url, masked_xpath_link = pair
      if index > 0 && masked_xpath_link.nil?
        prefix_length = index
        unless feed_prefix_xpaths_by_length.key?(prefix_length)
          feed_prefix_xpaths_by_length[prefix_length] = []
        end
        feed_prefix_xpaths_by_length[prefix_length] << masked_xpath
        break
      elsif feed_item_url != masked_xpath_link[:canonical_url]
        break # Not a prefix
      end
    end
  end

  collapsed_links_by_masked_xpath.each do |masked_xpath, masked_xpath_links|
    feed_suffix_start_index = feed_item_urls.index(masked_xpath_links[0][:canonical_url])
    next if feed_suffix_start_index.nil?

    is_suffix = true
    feed_item_urls[feed_suffix_start_index..-1].zip(masked_xpath_links).each_with_index do |pair, index|
      feed_item_url, masked_xpath_link = pair
      if feed_item_url.nil?
        break # suffix found
      elsif masked_xpath_link.nil?
        is_suffix = false
        break
      elsif feed_item_url != masked_xpath_link[:canonical_url]
        is_suffix = false
        break
      end
    end
    next unless is_suffix

    target_prefix_length = feed_suffix_start_index
    next unless feed_prefix_xpaths_by_length.key?(target_prefix_length)

    masked_prefix_xpath = feed_prefix_xpaths_by_length[target_prefix_length][0]
    logger.log("Found partition with two xpaths: #{target_prefix_length} + #{masked_xpath_links.length}")
    prefix_collapsion_log_str = get_collapsion_log_str(masked_prefix_xpath, links_by_masked_xpath, collapsed_links_by_masked_xpath)
    logger.log("Prefix xpath: #{masked_prefix_xpath}#{prefix_collapsion_log_str}")
    suffix_collapsion_log_str = get_collapsion_log_str(masked_xpath, links_by_masked_xpath, collapsed_links_by_masked_xpath)
    logger.log("Suffix xpath: #{masked_xpath}#{suffix_collapsion_log_str}")

    combined_links = collapsed_links_by_masked_xpath[masked_prefix_xpath] + masked_xpath_links
    combined_urls = combined_links.map { |link| link[:canonical_url] }
    combined_urls_set = combined_urls.to_set
    if combined_urls.length != combined_urls_set.length
      logger.log("Combination has all feed links but also duplicates: #{combined_urls}")
      next
    end

    logger.log("Combination is good")
    return { pattern: "archives_2xpaths", links: combined_links }
  end

  nil
end

def get_single_masked_xpaths(xpath)
  match_datas = xpath.to_enum(:scan, /\[\d+\]/).map { Regexp.last_match }
  match_datas.map do |match_data|
    start, finish = match_data.offset(0)
    xpath[0..start] + '*' + xpath[(finish - 1)..-1]
  end
end

def get_double_masked_xpaths(xpath)
  match_datas = xpath.to_enum(:scan, /\[\d+\]/).map { Regexp.last_match }
  match_datas.combination(2).map do |match_data1, match_data2|
    start1, finish1 = match_data1.offset(0)
    start2, finish2 = match_data2.offset(0)
    xpath[0..start1] + '*' +
      xpath[(finish1 - 1)..start2] + '*' +
      xpath[(finish2 - 1)..-1]
  end
end

def get_triple_masked_xpaths(xpath)
  match_datas = xpath.to_enum(:scan, /\[\d+\]/).map { Regexp.last_match }
  match_datas.combination(3).map do |match_data1, match_data2, match_data3|
    start1, finish1 = match_data1.offset(0)
    start2, finish2 = match_data2.offset(0)
    start3, finish3 = match_data3.offset(0)
    xpath[0..start1] + '*' +
      xpath[(finish1 - 1)..start2] + '*' +
      xpath[(finish2 - 1)..start3] + '*' +
      xpath[(finish3 - 1)..-1]
  end
end

def get_collapsion_log_str(masked_xpath, links_by_masked_xpath, collapsed_links_by_masked_xpath)
  collapsed_length = collapsed_links_by_masked_xpath[masked_xpath].length
  uncollapsed_length = links_by_masked_xpath[masked_xpath].length
  if uncollapsed_length != collapsed_length
    " (collapsed #{uncollapsed_length} -> #{collapsed_length})"
  else
    ''
  end
end