require_relative 'canonical_link'
require_relative 'crawling'
require_relative 'feed_parsing'
require_relative 'historical_archives'
require_relative 'historical_archives_categories'
require_relative 'historical_archives_sort'
require_relative 'historical_common'
require_relative 'historical_paged'
require_relative 'http_client'
require_relative 'page_parsing'
require_relative 'progress_logger'
require_relative 'puppeteer_client'
require_relative 'structs'
require_relative 'util'

GuidedCrawlResult = Struct.new(:feed_result, :start_url, :curi_eq_cfg, :historical_result, :historical_error)
FeedResult = Struct.new(:feed_url, :feed_links)
HistoricalResult = Struct.new(:main_link, :pattern, :links, :count, :extra, keyword_init: true)

class GuidedCrawlError < StandardError
  def initialize(message, partial_result)
    @partial_result = partial_result
    super(message)
  end

  attr_reader :partial_result
end

def guided_crawl(start_url, crawl_ctx, http_client, puppeteer_client, progress_saver, logger)
  guided_crawl_result = GuidedCrawlResult.new
  begin
    feed_result = FeedResult.new
    guided_crawl_result.feed_result = feed_result
    progress_logger = ProgressLogger.new(progress_saver)

    start_link = to_canonical_link(start_url, logger)
    raise "Bad start url: #{start_url}" if start_link.nil?

    guided_crawl_result.start_url = "<a href=\"#{start_link.url}\">#{start_link.url}</a>"
    start_result = crawl_request(start_link, true, crawl_ctx, http_client, progress_logger, logger)
    progress_logger.save_status
    raise "Unexpected start result: #{start_result}" unless start_result.is_a?(Page) && start_result.content

    if is_feed(start_result.content, logger)
      start_page_link = nil
      start_page = nil
      feed_link = start_link
      feed_page = start_result
      feed_result.feed_url = "<a href=\"#{start_link.url}\">feed</a>"
    else
      start_page_link = start_link
      start_page = start_result
      crawl_ctx.seen_fetch_urls << start_result.fetch_uri.to_s
      feed_links = start_page
        .document
        .xpath("/html/head/link[@rel='alternate']")
        .to_a
        .filter { |link| %w[application/rss+xml application/atom+xml].include?(link.attributes["type"]&.value) }
        .map { |link| link.attributes["href"]&.value }
        .map { |url| to_canonical_link(url, logger, start_link.uri) }
        .filter { |link| link }
        .filter { |link| !link.url.end_with?("?alt=rss") }
        .filter { |link| !link.url.end_with?("/comments/feed/") }
        .filter { |link| !link.url.end_with?("/comments/feed") }
      raise "No feed links for #{start_page.fetch_uri}" if feed_links.empty?
      raise "Multiple feed links for #{start_page.fetch_uri}" if feed_links.length > 1

      feed_link = feed_links.first
      feed_result.feed_url = "<a href=\"#{feed_link.url}\">feed</a>"
      feed_request_result = crawl_request(feed_link, true, crawl_ctx, http_client, progress_logger, logger)
      progress_logger.save_status
      unless feed_request_result.is_a?(Page) && feed_request_result.content
        raise "Unexpected feed result: #{feed_request_result}"
      end

      feed_page = feed_request_result
    end

    crawl_ctx.seen_fetch_urls << feed_page.fetch_uri.to_s
    logger.info("Feed url: #{feed_page.curi}")

    feed_links = extract_feed_links(feed_page.content, feed_page.fetch_uri, logger)

    if start_page.nil?
      start_page_link, start_page = get_feed_start_page(
        feed_link, feed_links, crawl_ctx, http_client, progress_logger, logger
      )
    end

    feed_result.feed_links = feed_links.entry_links.length
    logger.info("title: #{feed_links.title}")
    logger.info("Root url: #{feed_links.root_link&.url}")
    logger.info("Entries in feed: #{feed_links.entry_links.length}")
    logger.info("Feed order is certain: #{feed_links.entry_links.is_order_certain}")

    raise "Feed is empty" if feed_links.entry_links.length == 0
    raise "Feed only has 1 item" if feed_links.entry_links.length == 1

    feed_entry_links_by_host = {}
    feed_links.entry_links.to_a.each do |entry_link|
      unless feed_entry_links_by_host.key?(entry_link.uri.host)
        feed_entry_links_by_host[entry_link.uri.host] = []
      end
      feed_entry_links_by_host[entry_link.uri.host] << entry_link
    end

    same_hosts = Set.new
    [[start_page_link, start_page], [feed_link, feed_page]].each do |link, page|
      if canonical_uri_same_path?(link.curi, page.curi) &&
        (feed_entry_links_by_host.key?(link.uri.host) || feed_entry_links_by_host.key?(page.fetch_uri.host))

        same_hosts << link.uri.host << page.fetch_uri.host
      end
    end

    unless feed_entry_links_by_host.keys.any? { |entry_host| same_hosts.include?(entry_host) }
      entry_link_from_popular_host = feed_entry_links_by_host
        .max { |host_links1, host_links2| host_links2[1].length <=> host_links1[1].length }
        .last
        .first
      entry_result = crawl_request(
        entry_link_from_popular_host, false, crawl_ctx, http_client, progress_logger, logger
      )
      progress_logger.save_status

      unless entry_result.is_a?(Page) && entry_result.content
        raise "Unexpected entry result: #{entry_result}"
      end

      if canonical_uri_same_path?(entry_link_from_popular_host.curi, entry_result.curi)
        same_hosts << entry_link_from_popular_host.uri.host << entry_result.fetch_uri.host
      end
    end

    curi_eq_cfg = CanonicalEqualityConfig.new(same_hosts, feed_links.generator == :tumblr)
    crawl_ctx.fetched_curis.update_equality_config(curi_eq_cfg)
    crawl_ctx.pptr_fetched_curis.update_equality_config(curi_eq_cfg)
    guided_crawl_result.curi_eq_cfg = curi_eq_cfg

    historical_error = nil
    if feed_links.entry_links.length >= 101
      logger.info("Feed is long with #{feed_links.entry_links.length} entries")
      historical_result = HistoricalResult.new(
        main_link: feed_link,
        pattern: "long_feed",
        links: feed_links.entry_links.to_a,
        count: feed_links.entry_links.length,
        extra: ""
      )
    else
      begin
        historical_result = guided_crawl_historical(
          start_page, feed_links.entry_links, feed_links.generator, crawl_ctx, curi_eq_cfg, http_client,
          puppeteer_client, progress_logger, logger
        )
      rescue => e
        historical_result = nil
        historical_error = e
      end
    end
    guided_crawl_result.historical_result = historical_result
    guided_crawl_result.historical_error = historical_error
    guided_crawl_result
  rescue => e
    raise GuidedCrawlError.new(e.message, guided_crawl_result), e
  end
end

def get_feed_start_page(feed_link, feed_links, crawl_ctx, mock_http_client, progress_logger, logger)
  if feed_links.root_link
    start_page_link = feed_links.root_link
    start_result = crawl_request(start_page_link, false, crawl_ctx, mock_http_client, progress_logger, logger)
    progress_logger.save_status
    if start_result.is_a?(Page) && start_result.content
      return [start_page_link, start_result]
    else
      logger.info("Root link page is malformed: #{start_result}")
    end
  end

  logger.info("Trying to discover start page")
  possible_start_uri = feed_link.uri
  loop do
    raise "Couldn't discover start link" if !possible_start_uri.path || possible_start_uri.path.empty?

    possible_start_uri.path = possible_start_uri.path.rpartition("/").first
    possible_start_page_link = to_canonical_link(possible_start_uri.to_s, logger)
    logger.info("Possible start link: #{possible_start_uri.to_s}")
    possible_start_result = crawl_request(
      possible_start_page_link, false, crawl_ctx, mock_http_client, progress_logger, logger
    )
    progress_logger.save_status
    next unless possible_start_result.is_a?(Page) && possible_start_result.content

    return [possible_start_page_link, possible_start_result]
  end
end

ARCHIVES_REGEX = "/(?:(?:[a-z]+-)?archives?|posts?|all(?:-[a-z]+)?)(?:\\.[a-z]+)?$"
MAIN_PAGE_REGEX = "/(?:blog|articles|writing|journal|essays)(?:\\.[a-z]+)?$"

def guided_crawl_historical(
  start_page, feed_entry_links, feed_generator, crawl_ctx, curi_eq_cfg, mock_http_client,
  puppeteer_client, progress_logger, logger
)
  archives_queue = []
  main_page_queue = []

  guided_seen_queryless_curis_set = CanonicalUriSet.new([], curi_eq_cfg)

  allowed_hosts = curi_eq_cfg.same_hosts.empty? ?
    [start_page.curi.host] :
    curi_eq_cfg.same_hosts

  start_page_all_links = extract_links(
    start_page.document, start_page.fetch_uri, nil, crawl_ctx.redirects, logger, true, true
  )
  start_page_allowed_hosts_links = start_page_all_links
    .filter { |link| allowed_hosts.include?(link.uri.host) }

  feed_entry_curis_set = feed_entry_links
    .to_a
    .map(&:curi)
    .to_canonical_uri_set(curi_eq_cfg)

  archives_categories_state = ArchivesCategoriesState.new

  if start_page.curi.trimmed_path&.match?(ARCHIVES_REGEX)
    archives_queue << start_page
  else
    main_page_queue << start_page
  end

  start_page_other_links = []
  start_page_allowed_hosts_links.each do |link|
    queryless_curi = canonical_uri_without_query(link.curi)
    next if guided_seen_queryless_curis_set.include?(queryless_curi)

    if link.curi.trimmed_path&.match?(ARCHIVES_REGEX)
      guided_seen_queryless_curis_set << queryless_curi
      archives_queue << link
    elsif link.curi.trimmed_path&.match?(MAIN_PAGE_REGEX)
      guided_seen_queryless_curis_set << queryless_curi
      main_page_queue << link
    else
      start_page_other_links << link
    end
  end

  logger.info("Start page and links: #{archives_queue.length} archives, #{main_page_queue.length} main page")

  result = guided_crawl_fetch_loop(
    [archives_queue, main_page_queue], nil, guided_seen_queryless_curis_set, archives_categories_state,
    feed_entry_links, feed_entry_curis_set, feed_generator, curi_eq_cfg, allowed_hosts, crawl_ctx,
    mock_http_client, puppeteer_client, progress_logger, logger
  )
  if result
    if result.count >= 11
      return result
    else
      logger.info("Got a result with #{result.count} historical links but it looks too small. Continuing just in case")
    end
  end

  raise "Too few entries in feed: #{feed_entry_links.length}" if feed_entry_links.length < 2
  feed_entry_links_arr = feed_entry_links.to_a
  entry1_page = crawl_request(
    feed_entry_links_arr[0], false, crawl_ctx, mock_http_client, progress_logger, logger
  )
  progress_logger.save_status
  entry2_page = crawl_request(
    feed_entry_links_arr[1], false, crawl_ctx, mock_http_client, progress_logger, logger
  )
  progress_logger.save_status
  raise "Couldn't fetch entry 1: #{entry1_page}" unless entry1_page.is_a?(Page) && entry1_page.document
  raise "Couldn't fetch entry 2: #{entry2_page}" unless entry2_page.is_a?(Page) && entry2_page.document

  entry1_links = extract_links(
    entry1_page.document, entry1_page.fetch_uri, allowed_hosts, crawl_ctx.redirects, logger, true, true
  )
  entry2_links = extract_links(
    entry2_page.document, entry1_page.fetch_uri, allowed_hosts, crawl_ctx.redirects, logger, true, true
  )
  entry1_curis_set = entry1_links
    .map(&:curi)
    .to_canonical_uri_set(curi_eq_cfg)

  two_entries_links = []
  entry2_curis_set = CanonicalUriSet.new([], curi_eq_cfg)
  entry2_links.each do |entry2_link|
    next if entry2_curis_set.include?(entry2_link.curi)

    entry2_curis_set << entry2_link.curi
    two_entries_links << entry2_link if entry1_curis_set.include?(entry2_link.curi)
  end

  two_entries_other_links = []
  two_entries_links.each do |link|
    queryless_curi = canonical_uri_without_query(link.curi)
    next if guided_seen_queryless_curis_set.include?(queryless_curi)

    if link.curi.trimmed_path&.match?(ARCHIVES_REGEX)
      guided_seen_queryless_curis_set << queryless_curi
      archives_queue << link
    elsif link.curi.trimmed_path&.match?(MAIN_PAGE_REGEX)
      guided_seen_queryless_curis_set << queryless_curi
      main_page_queue << link
    else
      two_entries_other_links << link
    end
  end

  logger.info("Two entries links: #{archives_queue.length} archives, #{main_page_queue.length} main page")

  result = guided_crawl_fetch_loop(
    [archives_queue, main_page_queue], result, guided_seen_queryless_curis_set, archives_categories_state,
    feed_entry_links, feed_entry_curis_set, feed_generator, curi_eq_cfg, allowed_hosts, crawl_ctx,
    mock_http_client, puppeteer_client, progress_logger, logger
  )
  if result
    if result.count >= 11
      return result
    else
      logger.info("Got a result with #{result.count} historical links but it looks too small. Continuing just in case")
    end
  end

  others_queue = []

  if feed_generator == :medium
    logger.info("Skipping other links because Medium")
    return result if result
  else
    filtered_two_entries_other_links = two_entries_other_links
      .filter { |link| !feed_entry_curis_set.include?(link.curi) }
    if filtered_two_entries_other_links.length > 10
      twice_filtered_two_entries_other_links = filtered_two_entries_other_links.filter do |link|
        !link.curi.trimmed_path&.match?(/\/\d\d\d\d(\/\d\d)?(\/\d\d)?$/)
      end
      logger.info("Two entries other links: filtering #{filtered_two_entries_other_links.length} -> #{twice_filtered_two_entries_other_links.length}")
    else
      twice_filtered_two_entries_other_links = filtered_two_entries_other_links
      logger.info("Two entries other links: #{twice_filtered_two_entries_other_links.length}")
    end

    twice_filtered_two_entries_other_links.each do |link|
      queryless_curi = canonical_uri_without_query(link.curi)
      next if guided_seen_queryless_curis_set.include?(queryless_curi)

      others_queue << link
    end

    filtered_start_page_other_links = start_page_other_links.filter do |link|
      level = link.curi.trimmed_path&.count("/")
      [nil, 1].include?(level) && !link.curi.trimmed_path&.match?(/\/\d\d\d\d(\/\d\d)?(\/\d\d)?$/)
    end
    are_any_feed_entries_top_level = feed_entry_links
      .to_a
      .any? { |entry_link| [nil, 1].include?(entry_link.curi.trimmed_path&.count("/")) }
    if are_any_feed_entries_top_level
      logger.info("Skipping start page other links because some feed entries are top level")
    else
      logger.info("Start page other links: #{filtered_start_page_other_links.length}")
      filtered_start_page_other_links.each do |link|
        queryless_curi = canonical_uri_without_query(link.curi)
        next if guided_seen_queryless_curis_set.include?(queryless_curi)

        others_queue << link
      end
    end

    result = guided_crawl_fetch_loop(
      [archives_queue, main_page_queue, others_queue], result, guided_seen_queryless_curis_set,
      archives_categories_state, feed_entry_links, feed_entry_curis_set, feed_generator, curi_eq_cfg,
      allowed_hosts, crawl_ctx, mock_http_client, puppeteer_client, progress_logger, logger
    )
    return result if result
  end

  logger.info("Pattern not detected")
  nil
end

def guided_crawl_fetch_loop(
  queues, initial_result, guided_seen_queryless_curis_set, archives_categories_state, feed_entry_links,
  feed_entry_curis_set, feed_generator, curi_eq_cfg, allowed_hosts, crawl_ctx, mock_http_client,
  puppeteer_client, progress_logger, logger
)
  logger.info("Guided crawl loop started")

  sorted_results = initial_result ? [initial_result] : []
  archives_queue, main_page_queue = queues
  had_archives = !archives_queue.empty?
  loop do
    active_queue_index = queues.index { |queue| !queue.empty? }
    break unless active_queue_index

    active_queue = queues[active_queue_index]
    link_or_page = active_queue.shift
    if link_or_page.is_a?(Link)
      link = link_or_page
      next if crawl_ctx.fetched_curis.include?(link.curi)

      page = crawl_request(link, false, crawl_ctx, mock_http_client, progress_logger, logger)
      unless page.is_a?(Page) && page.document
        logger.info("Couldn't fetch link: #{page}")
        next
      end
    elsif link_or_page.is_a?(Page)
      page = link_or_page
      link = to_canonical_link(page.fetch_uri.to_s, logger)
    else
      raise "Neither link nor page in the queue: #{link_or_page}"
    end

    if is_puppeteer_match(page)
      # Without puppeteer match, it's better to check for historical, then save a colored rectangle
      # With puppeteer match, there will be more waits so log a simple rectangle before that
      progress_logger.save_status
    end

    pptr_page = crawl_with_puppeteer_if_match(
      page, feed_entry_curis_set, puppeteer_client, crawl_ctx, progress_logger, logger
    )

    page_all_links = extract_links(
      pptr_page.document, pptr_page.fetch_uri, nil, crawl_ctx.redirects, logger, true, true
    )

    page_allowed_hosts_links = page_all_links
      .filter { |page_link| allowed_hosts.include?(page_link.uri.host) }
    page_allowed_hosts_links.each do |page_link|
      queryless_curi = canonical_uri_without_query(page_link.curi)
      next if guided_seen_queryless_curis_set.include?(queryless_curi)

      if page_link.curi.trimmed_path&.match?(ARCHIVES_REGEX)
        guided_seen_queryless_curis_set << queryless_curi
        archives_queue << page_link
        had_archives = true
        logger.info("Enqueueing archives link: #{page_link.curi}")
      elsif page_link.curi.trimmed_path&.match?(MAIN_PAGE_REGEX)
        guided_seen_queryless_curis_set << queryless_curi
        main_page_queue << page_link
        logger.info("Enqueueing main page link: #{page_link.curi}")
      end
    end

    page_curis_set = page_all_links
      .map(&:curi)
      .to_canonical_uri_set(curi_eq_cfg)
    page_results = try_extract_historical(
      link, pptr_page, page_all_links, page_curis_set, feed_entry_links, feed_entry_curis_set, feed_generator,
      curi_eq_cfg, archives_categories_state, progress_logger, logger
    )
    progress_logger.save_status
    page_results.each do |page_result|
      insert_sorted_result(page_result, sorted_results)
    end

    if had_archives && archives_queue.empty? && !sorted_results.empty?
      postprocessed_result = postprocess_results(
        sorted_results, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, progress_logger, logger
      )
      if postprocessed_result
        if postprocessed_result.count >= 21
          logger.info("Guided crawl loop finished with best result of #{postprocessed_result.count} links")
          return postprocessed_result
        else
          logger.info("Went through all the archives but the best result only has #{postprocessed_result.count} links. Checking others just in case")
          sorted_results.prepend(postprocessed_result)
        end
      end
    end
  end

  postprocessed_result = postprocess_results(
    sorted_results, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, progress_logger, logger
  )
  if postprocessed_result
    logger.info("Guided crawl loop finished with best result of #{postprocessed_result.count} links")
    return postprocessed_result
  end

  logger.info("Guided crawl loop finished, no result")
  nil
end

def try_extract_historical(
  page_link, page, page_links, page_curis_set, feed_entry_links, feed_entry_curis_set, feed_generator,
  curi_eq_cfg, archives_categories_state, progress_logger, logger
)
  logger.info("Trying to extract historical from #{page.fetch_uri}")
  results = []

  archives_almost_match_threshold = get_archives_almost_match_threshold(feed_entry_links.length)
  extractions_by_masked_xpath_by_star_count = get_extractions_by_masked_xpath_by_star_count(
    page_links, feed_entry_links, feed_entry_curis_set, curi_eq_cfg, archives_almost_match_threshold, logger
  )

  archives_results = try_extract_archives(
    page_link, page, page_links, page_curis_set, feed_entry_links, feed_entry_curis_set, feed_generator,
    extractions_by_masked_xpath_by_star_count, archives_almost_match_threshold, curi_eq_cfg, logger
  )
  results.push(*archives_results)

  archives_categories_result = try_extract_archives_categories(
    page_link, page, page_curis_set, feed_entry_links, feed_entry_curis_set,
    extractions_by_masked_xpath_by_star_count, archives_categories_state, curi_eq_cfg, logger
  )
  results << archives_categories_result if archives_categories_result

  page1_result = try_extract_page1(
    page_link, page, page_links, page_curis_set, feed_entry_links, feed_entry_curis_set, feed_generator,
    curi_eq_cfg, logger
  )
  results << page1_result if page1_result

  progress_logger.log_historical unless results.empty?

  results
end

def insert_sorted_result(new_result, sorted_results)
  insert_index = sorted_results
    .find_index { |result| speculative_count_better_than(new_result, result) }
  if insert_index
    sorted_results.insert(insert_index, new_result)
  else
    sorted_results << new_result
  end
end

def speculative_count_better_than(result1, result2)
  result1_matching_feed = !(result1.is_a?(PostprocessedResult) && !result1.is_matching_feed)
  result2_matching_feed = !(result2.is_a?(PostprocessedResult) && !result2.is_matching_feed)

  (result1_matching_feed && !result2_matching_feed) ||
    (!(!result1_matching_feed && result2_matching_feed) &&
      result1.speculative_count > result2.speculative_count)
end

def speculative_count_equal(result1, result2)
  result1_matching_feed = !(result1.is_a?(PostprocessedResult) && !result1.is_matching_feed)
  result2_matching_feed = !(result2.is_a?(PostprocessedResult) && !result2.is_matching_feed)

  result1_matching_feed == result2_matching_feed && result1.speculative_count == result2.speculative_count
end

def postprocess_results(
  sorted_results, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, progress_logger, logger
)
  sorted_results_log = sorted_results.map do |result|
    [result.class.name, result.main_link.url, result.speculative_count]
  end
  logger.info("Postprocessing #{sorted_results.length} results: #{sorted_results_log}")

  until sorted_results.empty?
    result = sorted_results.shift
    if result.count
      pp_result = result
    else
      if result.is_a?(ArchivesMediumPinnedEntryResult)
        pp_result = postprocess_archives_medium_pinned_entry_result(
          result, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, progress_logger, logger
        )
      elsif result.is_a?(ArchivesShuffledResults)
        pp_result = postprocess_archives_shuffled_results(
          result, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, progress_logger, logger
        )
      elsif result.is_a?(ArchivesCategoriesResult)
        pp_result = postprocess_archives_categories_result(
          result, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, progress_logger, logger
        )
      elsif result.is_a?(Page1Result)
        # If page 1 result looks the best, check just page 2 in case it was a scam
        pp_result = postprocess_page1_result(
          result, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, progress_logger, logger
        )
      elsif result.is_a?(PartialPagedResult)
        pp_result = postprocess_paged_result(
          result, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, progress_logger, logger
        )
      else
        raise "Unknown result type: #{result}"
      end
    end

    unless pp_result
      logger.info("Postprocessing failed for #{result.main_link.url}")
      next
    end

    if sorted_results.empty? ||
      speculative_count_better_than(pp_result, sorted_results.first) ||
      (!pp_result.is_a?(PartialPagedResult) && speculative_count_equal(pp_result, sorted_results.first))

      if pp_result.is_a?(PartialPagedResult)
        pp_result = postprocess_paged_result(
          pp_result, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, progress_logger, logger
        )
      end

      return pp_result
    end

    pp_log = [result.class.name, result.main_link.url, result.speculative_count]
    pp_log << :not_matching_feed if pp_result.is_a?(PostprocessedResult) && !pp_result.is_matching_feed
    logger.info("Inserting back postprocessed #{pp_log}")
    insert_sorted_result(pp_result, sorted_results)
  end

  nil
end

PostprocessedResult = Struct.new(
  :main_link, :pattern, :links, :speculative_count, :count, :is_matching_feed, :extra, keyword_init: true
)

def postprocess_archives_medium_pinned_entry_result(
  medium_result, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, progress_logger, logger
)
  pinned_entry_page = crawl_request(
    medium_result.pinned_entry_link, false, crawl_ctx, mock_http_client, progress_logger, logger
  )
  progress_logger.log_and_save_postprocessing
  unless pinned_entry_page.is_a?(Page) && pinned_entry_page.document
    logger.info("Couldn't fetch first Medium link during result postprocess: #{pinned_entry_page}")
    return nil
  end

  pinned_entry_page_links = extract_links(
    pinned_entry_page.document, pinned_entry_page.fetch_uri, [pinned_entry_page.fetch_uri.host],
    crawl_ctx.redirects, logger
  )

  sorted_links = historical_archives_medium_sort_finish(
    medium_result.pinned_entry_link, pinned_entry_page_links, medium_result.other_links_dates, curi_eq_cfg
  )
  unless sorted_links
    logger.info("Couldn't sort links during result postprocess")
    return nil
  end

  return nil unless compare_with_feed(sorted_links, feed_entry_links, curi_eq_cfg, logger)

  PostprocessedResult.new(
    main_link: medium_result.main_link,
    pattern: medium_result.pattern,
    links: sorted_links,
    speculative_count: sorted_links.length,
    count: sorted_links.length,
    is_matching_feed: true,
    extra: medium_result.extra
  )
end

def postprocess_archives_shuffled_results(
  shuffled_results, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, progress_logger, logger
)
  pages_by_canonical_url = {}
  sorted_tentative_results = shuffled_results.results.sort_by do |tentative_result|
    tentative_result.speculative_count
  end
  logger.info("Archives shuffled counts: #{sorted_tentative_results.map(&:speculative_count)}")

  best_result = nil
  sorted_tentative_results.each do |tentative_result|
    logger.info("Postprocessing shuffled result of #{tentative_result.speculative_count}")
    sorted_links, is_matching_feed = postprocess_sort_links_maybe_dates(
      tentative_result.links_maybe_dates, feed_entry_links, curi_eq_cfg, pages_by_canonical_url, crawl_ctx,
      mock_http_client, progress_logger, logger
    )
    return best_result unless sorted_links

    best_result = PostprocessedResult.new(
      main_link: shuffled_results.main_link,
      pattern: tentative_result.pattern,
      links: sorted_links,
      speculative_count: sorted_links.length,
      count: sorted_links.length,
      is_matching_feed: is_matching_feed,
      extra: tentative_result.extra
    )
  end

  best_result
end

def postprocess_archives_categories_result(
  archives_categories_result, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, progress_logger,
  logger
)
  sorted_links, is_matching_feed = postprocess_sort_links_maybe_dates(
    archives_categories_result.links_maybe_dates, feed_entry_links, curi_eq_cfg, {}, crawl_ctx,
    mock_http_client, progress_logger, logger
  )
  return nil unless sorted_links

  PostprocessedResult.new(
    main_link: archives_categories_result.main_link,
    pattern: archives_categories_result.pattern,
    links: sorted_links,
    speculative_count: sorted_links.length,
    count: sorted_links.length,
    is_matching_feed: is_matching_feed,
    extra: archives_categories_result.extra
  )
end

def postprocess_page1_result(
  page1_result, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, progress_logger, logger
)
  page2 = crawl_request(
    page1_result.link_to_page2, false, crawl_ctx, mock_http_client, progress_logger, logger
  )
  progress_logger.log_and_save_postprocessing
  unless page2 && page2.is_a?(Page) && page2.document
    logger.info("Page 2 is not a page: #{page2}")
    return nil
  end

  paged_result = try_extract_page2(page2, page1_result.paged_state, feed_entry_links, curi_eq_cfg, logger)
  paged_result
end

def postprocess_paged_result(
  paged_result, feed_entry_links, curi_eq_cfg, crawl_ctx, mock_http_client, progress_logger, logger
)

  while paged_result.is_a?(PartialPagedResult)
    progress_logger.log_count(paged_result.speculative_count - 1)
    page = crawl_request(
      paged_result.link_to_next_page, false, crawl_ctx, mock_http_client, progress_logger, logger
    )
    progress_logger.log_and_save_postprocessing
    unless page && page.is_a?(Page) && page.document
      logger.info("Page #{paged_result.page_number} is not a page: #{page}")
      return nil
    end

    paged_result = try_extract_next_page(
      page, paged_result.paged_state, feed_entry_links, curi_eq_cfg, logger
    )
  end

  if paged_result
    progress_logger.log_count(paged_result.count)
  else
    progress_logger.log_count(nil)
  end
  paged_result
end

def postprocess_sort_links_maybe_dates(
  links_maybe_dates, feed_entry_links, curi_eq_cfg, pages_by_canonical_url, crawl_ctx, mock_http_client,
  progress_logger, logger
)
  result_pages = []
  sort_state = nil
  links_with_dates, links_without_dates = links_maybe_dates.partition { |_, maybe_date| maybe_date }
  links_without_dates = links_without_dates.map(&:first)
  crawled_links, links_to_crawl = links_without_dates.partition do |link|
    pages_by_canonical_url.key?(link.curi.to_s)
  end

  crawled_links.each do |link|
    page = pages_by_canonical_url[link.curi.to_s]
    sort_state = historical_archives_sort_add(page, sort_state, logger)
    return nil unless sort_state

    result_pages << page
  end

  links_to_crawl.each_with_index do |link, index|
    page = crawl_request(link, false, crawl_ctx, mock_http_client, progress_logger, logger)
    unless page.is_a?(Page) && page.document
      logger.info("Couldn't fetch link during result postprocess: #{page}")
      progress_logger.log_and_save_postprocessing
      return nil
    end

    sort_state = historical_archives_sort_add(page, sort_state, logger)
    unless sort_state
      progress_logger.log_and_save_postprocessing
      return nil
    end

    progress_logger.log_and_save_postprocessing_remaining(links_to_crawl.length - index - 1)
    result_pages << page
    pages_by_canonical_url[page.curi.to_s] = page
  end

  sorted_links = historical_archives_sort_finish(
    links_with_dates, links_without_dates, sort_state, logger
  )
  return nil unless sorted_links

  [sorted_links, compare_with_feed(sorted_links, feed_entry_links, curi_eq_cfg, logger)]
end

def canonical_uri_without_query(curi)
  CanonicalUri.new(curi.host, curi.port, curi.path, nil)
end

def compare_with_feed(sorted_links, feed_entry_links, curi_eq_cfg, logger)
  if feed_entry_links.is_order_certain
    sorted_curis = sorted_links.map(&:curi)
    curis_set = sorted_curis.to_canonical_uri_set(curi_eq_cfg)
    present_feed_entry_links = feed_entry_links.filter_included(curis_set)
    is_matching_feed = present_feed_entry_links.sequence_match?(sorted_curis, curi_eq_cfg)
    unless is_matching_feed
      logger.info("Sorted links")
      logger.info("#{sorted_curis.map(&:to_s)}")
      logger.info("are not matching filtered feed:")
      logger.info(present_feed_entry_links)
      return false
    end
  end

  true
end