require 'set'
require_relative 'crawling'
require_relative 'feed_parsing'
require_relative 'historical_archives'
require_relative 'historical_paged'
require_relative 'run_common'
require_relative 'util'

HISTORICAL_RESULT_COLUMNS = [
  [:start_url, :neutral],
  [:comment, :neutral],
  [:gt_pattern, :neutral],
  [:feed_url, :neutral_present],
  [:feed_links, :boolean],
  [:found_items_count, :neutral_present],
  [:all_items_found, :boolean],
  [:historical_links_matching, :boolean],
  [:no_regression, :neutral],
  [:historical_links_pattern, :neutral_present],
  [:historical_links_count, :neutral_present],
  [:main_url, :neutral_present],
  [:oldest_link, :neutral_present],
  [:extra, :neutral],
  [:total_time, :neutral]
]

class HistoricalRunnable
  def initialize
    @result_column_names = to_column_names(HISTORICAL_RESULT_COLUMNS)
  end

  def run(start_link_id, save_successes, db, logger)
    discover_historical_entries_from_scratch(start_link_id, save_successes, db, logger)
  end

  attr_reader :result_column_names
end

def discover_historical_entries_from_scratch(start_link_id, save_successes, db, logger)
  logger.log("Discover historical entries from scratch started")

  start_link_url = db.exec_params('select url from start_links where id = $1', [start_link_id])[0]["url"]
  result = RunResult.new(HISTORICAL_RESULT_COLUMNS)
  result.start_url = "<a href=\"#{start_link_url}\">#{start_link_url}</a>"
  start_time = monotonic_now

  begin
    db.exec_params("delete from historical where start_link_id = $1", [start_link_id])

    comment_row = db.exec_params(
      'select severity, issue from known_issues where start_link_id = $1',
      [start_link_id]
    ).first
    if comment_row
      result.comment = comment_row["issue"]
      if comment_row["severity"] == "fail"
        result.comment_status = :failure
        raise "Known issue: #{comment_row["issue"]}"
      end
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
      "select content, canonical_url, fetch_url from pages where id in (select page_id from feeds where start_link_id = $1)",
      [start_link_id]
    ).first
    raise "Feed not found in db" unless feed_row

    result.feed_url = "<a href=\"#{feed_row["fetch_url"]}\">#{feed_row["canonical_url"]}</a>"
    feed_content = unescape_bytea(feed_row["content"])
    feed_fetch_uri = URI(feed_row["fetch_url"])
    feed_urls = extract_feed_urls(feed_content, logger)
    item_links = feed_urls
      .item_urls
      .map { |url| to_canonical_link(url, logger, feed_fetch_uri) }
      .map { |link| follow_cached_redirects(link, redirects) }
    feed_url = feed_row["canonical_url"]
    item_canonical_urls = item_links.map(&:canonical_url)

    result.feed_links = item_links.length
    found_items_count = item_canonical_urls.count do |item_canonical_url|
      db
        .exec_params(
          "select count(*) from pages where content is not null and start_link_id = $1 and canonical_url = $2",
          [start_link_id, item_canonical_url]
        )
        .first["count"]
        .to_i == 1
    end
    logger.log("Found feed links: #{found_items_count}")
    result.found_items_count = found_items_count
    all_items_found = found_items_count == item_canonical_urls.length
    result.all_items_found = all_items_found
    raise "Not all items found" unless all_items_found

    historical_links = discover_historical_entries(
      start_link_id, feed_url, item_canonical_urls, redirects, db, logger
    )
    raise "Historical links not found" if historical_links.nil?
    logger.log("Newest to oldest:")
    historical_links[:links].each do |link|
      logger.log(link.canonical_url)
    end

    entries_count = historical_links[:links].length
    oldest_link = historical_links[:links][-1]
    db.exec_params(
      "insert into historical (start_link_id, pattern, entries_count, main_page_canonical_url, oldest_entry_canonical_url) values ($1, $2, $3, $4, $5)",
      [start_link_id, historical_links[:pattern], entries_count, historical_links[:main_canonical_url], oldest_link.canonical_url]
    )

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
      gt_main_url = gt_row["main_page_canonical_url"]
      if gt_main_url == historical_links[:main_canonical_url]
        result.main_url = "<a href=\"#{historical_links[:main_fetch_url]}\">#{historical_links[:main_canonical_url]}</a>"
      else
        result.main_url = "<a href=\"#{historical_links[:main_fetch_url]}\">#{historical_links[:main_canonical_url]}</a><br>(#{gt_row["main_page_canonical_url"]})"
      end

      gt_oldest_canonical_url = gt_row["oldest_entry_canonical_url"]
      if gt_oldest_canonical_url == oldest_link.canonical_url
        result.oldest_link_status = :success
        result.oldest_link = "<a href=\"#{oldest_link.url}\">#{oldest_link.canonical_url}</a>"
      else
        historical_links_matching = false
        result.oldest_link_status = :failure
        if oldest_link.canonical_url == gt_oldest_canonical_url
          result.oldest_link = "<a href=\"#{oldest_link.url}\">#{oldest_link.canonical_url}</a>"
        else
          result.oldest_link = "<a href=\"#{oldest_link.url}\">#{oldest_link.canonical_url}</a><br>(#{gt_oldest_canonical_url})"
        end
      end

      result.historical_links_matching = historical_links_matching

      has_succeeded_before = db
        .exec_params("select count(*) from successes where start_link_id = $1", [start_link_id])
        .first["count"]
        .to_i == 1
      if has_succeeded_before
        result.no_regression = historical_links_matching
        result.no_regression_status = historical_links_matching ? :success : :failure
      end

      if save_successes && !has_succeeded_before && historical_links_matching
        logger.log("First success for this id, saving")
        db.exec_params("insert into successes (start_link_id, timestamp) values ($1, now())", [start_link_id])
      end
    else
      result.historical_links_matching = '?'
      result.historical_links_matching_status = :neutral
      result.historical_links_pattern = historical_links[:pattern]
      result.historical_links_count = entries_count
      result.main_url = "<a href=\"#{historical_links[:main_fetch_url]}\">#{historical_links[:main_canonical_url]}</a>"
      result.oldest_link = "<a href=\"#{oldest_link.url}\">#{oldest_link.canonical_url}</a>"
    end

    result.extra = historical_links[:extra]

    logger.log("Discover historical entries from scratch finished")
    result
  rescue => e
    raise RunError.new(e.message, result), e
  ensure
    result.total_time = (monotonic_now - start_time).to_i
  end
end

def discover_historical_entries(start_link_id, feed_url, feed_item_urls, redirects, db, logger)
  logger.log("Discover historical entries started")

  best_result = nil
  best_result_pattern = nil
  best_result_subpattern_priority = nil
  best_count = 0
  db.transaction do |transaction|
    transaction.exec_params(
      "declare pages_cursor cursor for "\
      "select canonical_url, fetch_url, content_type, content from pages "\
      "where start_link_id = $1 and content is not null and canonical_url != $2"\
      "order by length(canonical_url) asc",
      [start_link_id, feed_url]
    )

    feed_item_urls_set = feed_item_urls.to_set

    loop do
      rows = transaction.exec("fetch next from pages_cursor")
      if rows.cmd_tuples == 0
        break
      end
      row = rows.first

      page = Page.new(row["canonical_url"], URI(row["fetch_url"]), start_link_id, row["content_type"], unescape_bytea(row["content"]))
      # Don't pass allowed hosts so that the order of links is preserved
      page_links = extract_links(page, nil, redirects, logger, true, true)
      page_urls_set = page_links
        .map(&:canonical_url)
        .to_set

      adjusted_best_count = best_result_pattern == :paged ? best_count - 1 : best_count
      archives_result = try_extract_archives(
        page, page_links, page_urls_set, feed_item_urls, feed_item_urls_set, best_result_subpattern_priority,
        adjusted_best_count, logger
      )
      if archives_result
        best_result = archives_result[:best_result]
        best_result_subpattern_priority = archives_result[:subpattern_priority]
        best_result_pattern = :archives
        best_count = archives_result[:count]
      end

      paged_result = try_extract_paged(
        page, page_links, page_urls_set, feed_item_urls, feed_item_urls_set, best_count,
        start_link_id, redirects, db, logger
      )
      if paged_result
        best_result = paged_result[:best_result]
        best_result_subpattern_priority = paged_result[:subpattern_priority]
        best_result_pattern = :paged
        best_count = paged_result[:count]
      end
    end
  end

  logger.log("Discover historical entries finished")
  best_result
end