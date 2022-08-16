require_relative 'canonical_link'
require_relative 'crawling'
require_relative 'feed_parsing'
require_relative 'historical_archives'
require_relative 'historical_archives_categories'
require_relative 'historical_archives_sort'
require_relative 'historical_common'
require_relative 'historical_paged'
require_relative 'historical_tumblr_api'
require_relative 'http_client'
require_relative 'page_parsing'
require_relative 'progress_logger'
require_relative 'puppeteer_client'
require_relative 'structs'
require_relative 'title'
require_relative 'util'

GuidedCrawlResult = Struct.new(:feed_result, :start_url, :curi_eq_cfg, :historical_result, :historical_error)
FeedResult = Struct.new(:feed_url, :feed_links, :feed_matching_titles, :feed_matching_titles_status)
HistoricalResult = Struct.new(
  :blog_link, :main_link, :pattern, :links, :count, :discarded_feed_entry_urls, :post_categories, :extra,
  keyword_init: true
)

class GuidedCrawlError < StandardError
  def initialize(message, partial_result)
    @partial_result = partial_result
    super(message)
  end

  attr_reader :partial_result
end

def guided_crawl(
  discovered_start_page, start_feed, crawl_ctx, http_client, puppeteer_client, progress_saver, logger
)
  guided_crawl_result = GuidedCrawlResult.new
  begin
    feed_result = FeedResult.new
    guided_crawl_result.feed_result = feed_result
    progress_logger = ProgressLogger.new(progress_saver)

    logger.info("Feed url: #{start_feed.final_url}")
    feed_result.feed_url = "<a href=\"#{start_feed.final_url}\">feed</a>"

    feed_link = to_canonical_link(start_feed.url, logger)
    feed_final_link = to_canonical_link(start_feed.final_url, logger)

    parsed_feed = parse_feed(start_feed.content, feed_final_link.uri, logger)
    feed_result.feed_links = parsed_feed.entry_links.length
    raise "Feed is empty" if parsed_feed.entry_links.length == 0
    raise "Feed only has 1 item" if parsed_feed.entry_links.length == 1

    if discovered_start_page
      logger.info("Discovered start page is present")
      guided_crawl_result.start_url = "<a href=\"#{discovered_start_page.url}\">#{discovered_start_page.url}</a>"

      start_page_link = to_canonical_link(discovered_start_page.url, logger)
      start_page_final_link = to_canonical_link(discovered_start_page.final_url, logger)
      start_page_document = parse_html5(discovered_start_page.content, logger)
      start_page = Page.new(
        start_page_final_link.curi,
        start_page_final_link.uri,
        discovered_start_page.content,
        start_page_document
      )
    else
      logger.info("Discovered start page is absent")
      guided_crawl_result.start_url = "<a href=\"#{start_feed.url}\">#{start_feed.url}</a>"
      start_page_link, start_page = get_feed_start_page(
        feed_link, parsed_feed, crawl_ctx, http_client, progress_logger, logger
      )
      start_page_final_link = to_canonical_link(start_page.fetch_uri.to_s, logger)
    end

    feed_entry_links_by_host = {}
    parsed_feed.entry_links.to_a.each do |entry_link|
      unless feed_entry_links_by_host.key?(entry_link.uri.host)
        feed_entry_links_by_host[entry_link.uri.host] = []
      end
      feed_entry_links_by_host[entry_link.uri.host] << entry_link
    end

    same_hosts = Set.new
    [[start_page_link, start_page_final_link], [feed_link, feed_final_link]].each do |link, final_link|
      if canonical_uri_same_path?(link.curi, final_link.curi) &&
        (feed_entry_links_by_host.key?(link.uri.host) || feed_entry_links_by_host.key?(final_link.uri.host))

        same_hosts << link.uri.host << final_link.uri.host
      end
    end

    unless feed_entry_links_by_host.keys.any? { |entry_host| same_hosts.include?(entry_host) }
      logger.info("Feed entry links come from a different host than feed and start page")
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

    logger.info("Same hosts: #{same_hosts}")

    curi_eq_cfg = CanonicalEqualityConfig.new(same_hosts, parsed_feed.generator == :tumblr)
    crawl_ctx.fetched_curis.update_equality_config(curi_eq_cfg)
    crawl_ctx.pptr_fetched_curis.update_equality_config(curi_eq_cfg)
    guided_crawl_result.curi_eq_cfg = curi_eq_cfg

    feed_entry_curis_titles_map = CanonicalUriMap.new(curi_eq_cfg)
    parsed_feed.entry_links.to_a.each do |entry_link|
      feed_entry_curis_titles_map.add(entry_link, entry_link.title)
    end
    initial_blog_link = parsed_feed.root_link || start_page_final_link

    historical_error = nil
    if parsed_feed.entry_links.length <= 100
      begin
        if parsed_feed.generator != :tumblr
          crawl_historical_result = guided_crawl_historical(
            start_page, parsed_feed.entry_links, feed_entry_curis_titles_map, parsed_feed.generator,
            initial_blog_link, crawl_ctx, curi_eq_cfg, http_client, puppeteer_client, progress_logger, logger
          )
        else
          crawl_historical_result = get_tumblr_api_historical(
            parsed_feed.root_link.uri.hostname, crawl_ctx, http_client, progress_logger, logger
          )
        end

        if crawl_historical_result
          historical_curis_set = crawl_historical_result
            .links
            .map(&:curi)
            .to_canonical_uri_set(curi_eq_cfg)
          discarded_feed_entry_urls = parsed_feed
            .entry_links
            .to_a
            .filter { |entry_link| !historical_curis_set.include?(entry_link.curi) }
            .map(&:url)
          if crawl_historical_result.class.method_defined?(:post_categories)
            post_categories = crawl_historical_result.post_categories
          else
            post_categories = nil
          end

          historical_result = HistoricalResult.new(
            blog_link: crawl_historical_result.main_link,
            main_link: crawl_historical_result.main_link,
            pattern: crawl_historical_result.pattern,
            links: crawl_historical_result.links,
            count: crawl_historical_result.count,
            discarded_feed_entry_urls: discarded_feed_entry_urls,
            post_categories: post_categories,
            extra: crawl_historical_result.extra
          )
        else
          historical_result = nil
        end
      rescue => e
        historical_result = nil
        historical_error = e
      end
    else
      logger.info("Feed is long with #{parsed_feed.entry_links.length} entries")
      historical_result = HistoricalResult.new(
        blog_link: initial_blog_link,
        main_link: feed_link,
        pattern: "long_feed",
        links: parsed_feed.entry_links.to_a,
        count: parsed_feed.entry_links.length,
        discarded_feed_entry_urls: [],
        extra: ""
      )
    end

    if historical_result
      historical_result.links = fetch_missing_titles(
        historical_result.links, parsed_feed.entry_links.length, feed_entry_curis_titles_map,
        parsed_feed.generator, crawl_ctx, http_client, progress_logger, logger
      )
      extra_newline = historical_result.extra.empty? ? "" : "<br>"
      historical_result.extra += "#{extra_newline}title_xpaths: #{count_link_title_sources(historical_result.links)}"
      feed_links_matching_result = parsed_feed.entry_links.sequence_match(
        historical_result.links.map(&:curi), curi_eq_cfg
      )
      feed_titles_present = parsed_feed.entry_links.to_a.all?(&:title)
      if feed_links_matching_result && feed_titles_present
        matching_titles, mismatching_titles = feed_links_matching_result
          .zip(historical_result.links[...feed_links_matching_result.length])
          .partition do |feed_entry_link, result_link|
          feed_entry_link.title.nil? ||
            result_link.title.equalized_value == feed_entry_link.title.equalized_value
        end
        mismatching_titles.each do |feed_entry_link, result_link|
          logger.info("Title mismatch with feed: #{print_title(result_link.title)} != feed \"#{feed_entry_link.title.value}\"")
        end
        if matching_titles.length == feed_links_matching_result.length
          feed_result.feed_matching_titles = "#{matching_titles.length}"
          feed_result.feed_matching_titles_status = :success
        else
          feed_result.feed_matching_titles = "#{matching_titles.length} (#{feed_links_matching_result.length})"
          feed_result.feed_matching_titles_status = :failure
        end
      else
        feed_result.feed_matching_titles_status = :neutral
      end
    else
      feed_result.feed_matching_titles_status = :neutral
    end

    guided_crawl_result.historical_result = historical_result
    guided_crawl_result.historical_error = historical_error
    guided_crawl_result
  rescue => e
    raise GuidedCrawlError.new(e.message, guided_crawl_result), e
  end
end

def get_feed_start_page(feed_link, feed_links, crawl_ctx, http_client, progress_logger, logger)
  if feed_links.root_link
    start_page_link = feed_links.root_link
    start_result = crawl_request(start_page_link, false, crawl_ctx, http_client, progress_logger, logger)
    progress_logger.save_status
    if start_result.is_a?(Page) && start_result.content
      logger.info("Using start page from root link: #{start_page_link.url}")
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
      possible_start_page_link, false, crawl_ctx, http_client, progress_logger, logger
    )
    progress_logger.save_status
    next unless possible_start_result.is_a?(Page) && possible_start_result.content

    return [possible_start_page_link, possible_start_result]
  end
end

ARCHIVES_REGEX = "/(?:[a-z-]*archives?|posts?|all(?:-[a-z]+)?)(?:\\.[a-z]+)?$"
MAIN_PAGE_REGEX = "/(?:blog|articles|writing|journal|essays)(?:\\.[a-z]+)?$"

def guided_crawl_historical(
  start_page, feed_entry_links, feed_entry_curis_titles_map, feed_generator, initial_blog_link, crawl_ctx,
  curi_eq_cfg, http_client, puppeteer_client, progress_logger, logger
)
  archives_queue = []
  main_page_queue = []

  guided_seen_queryless_curis_set = CanonicalUriSet.new([], curi_eq_cfg)
  allowed_hosts = curi_eq_cfg.same_hosts.empty? ? [start_page.curi.host] : curi_eq_cfg.same_hosts

  start_page_all_links = extract_links(
    start_page.document, start_page.fetch_uri, nil, crawl_ctx.redirects, logger, true, true
  )
  start_page_allowed_hosts_links = start_page_all_links
    .filter { |link| allowed_hosts.include?(link.uri.host) }

  archives_categories_state = ArchivesCategoriesState.new(initial_blog_link)

  guided_seen_queryless_curis_set << canonical_uri_without_query(start_page.curi)
  if start_page.curi.trimmed_path&.match?(ARCHIVES_REGEX)
    logger.info("Start page uri matches archives: #{start_page.fetch_uri.to_s}")
    archives_queue << start_page
  else
    logger.info("Start page uri doesn't match archives, let it be a main page: #{start_page.fetch_uri.to_s}")
    main_page_queue << start_page
  end

  start_page_other_links = []
  start_page_allowed_hosts_links.each do |link|
    queryless_curi = canonical_uri_without_query(link.curi)
    next if guided_seen_queryless_curis_set.include?(queryless_curi)

    if link.curi.trimmed_path&.match?(ARCHIVES_REGEX)
      guided_seen_queryless_curis_set << queryless_curi
      archives_queue << link
      logger.info("Enqueued archives: #{link.url}")
    elsif link.curi.trimmed_path&.match?(MAIN_PAGE_REGEX)
      guided_seen_queryless_curis_set << queryless_curi
      main_page_queue << link
      logger.info("Enqueued main page: #{link.url}")
    else
      start_page_other_links << link
    end
  end

  logger.info("Start page and links: #{archives_queue.length} archives, #{main_page_queue.length} main page, #{start_page_other_links.length} others")

  result = guided_crawl_fetch_loop(
    [archives_queue, main_page_queue], nil, guided_seen_queryless_curis_set, archives_categories_state,
    feed_entry_links, feed_entry_curis_titles_map, feed_generator, curi_eq_cfg, allowed_hosts, 1, crawl_ctx,
    http_client, puppeteer_client, progress_logger, logger
  )
  if result
    if result.count >= 11
      logger.info("Phase 1 succeeded")
      return result
    else
      logger.info("Got a result with #{result.count} historical links but it looks too small. Continuing just in case")
    end
  end

  raise "Too few entries in feed: #{feed_entry_links.length}" if feed_entry_links.length < 2

  feed_entry_links_arr = feed_entry_links.to_a
  entry1_page = crawl_request(feed_entry_links_arr[0], false, crawl_ctx, http_client, progress_logger, logger)
  progress_logger.save_status
  raise "Couldn't fetch entry 1: #{entry1_page}" unless entry1_page.is_a?(Page) && entry1_page.document

  entry2_page = crawl_request(feed_entry_links_arr[1], false, crawl_ctx, http_client, progress_logger, logger)
  progress_logger.save_status
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

  logger.info("Phase 2 (two entries) start links: #{archives_queue.length} archives, #{main_page_queue.length} main page, #{two_entries_other_links.length} others")

  result = guided_crawl_fetch_loop(
    [archives_queue, main_page_queue], result, guided_seen_queryless_curis_set, archives_categories_state,
    feed_entry_links, feed_entry_curis_titles_map, feed_generator, curi_eq_cfg, allowed_hosts, 2, crawl_ctx,
    http_client, puppeteer_client, progress_logger, logger
  )
  if result
    if result.count >= 11
      logger.info("Phase 2 succeeded")
      return result
    else
      logger.info("Got a result with #{result.count} historical links but it looks too small. Continuing just in case")
    end
  end

  others_queue = []

  if feed_generator == :medium
    logger.info("Skipping phase 3 because Medium")
    return result if result
  else
    filtered_two_entries_other_links = two_entries_other_links
      .filter { |link| !feed_entry_curis_titles_map.include?(link.curi) }
    if filtered_two_entries_other_links.length > 10
      twice_filtered_two_entries_other_links = filtered_two_entries_other_links.filter do |link|
        !link.curi.trimmed_path&.match?(/\/\d\d\d\d(\/\d\d)?(\/\d\d)?$/)
      end
      logger.info("Two entries other links: filtering #{filtered_two_entries_other_links.length} -> #{twice_filtered_two_entries_other_links.length}")
    else
      twice_filtered_two_entries_other_links = filtered_two_entries_other_links
      logger.info("Two entries other links: #{twice_filtered_two_entries_other_links.length}")
    end

    phase2_others_count = 0
    twice_filtered_two_entries_other_links.each do |link|
      queryless_curi = canonical_uri_without_query(link.curi)
      next if guided_seen_queryless_curis_set.include?(queryless_curi)

      others_queue << link
      phase2_others_count += 1
    end
    logger.info("Phase 3 links from phase 2: #{phase2_others_count}")

    filtered_start_page_other_links = start_page_other_links.filter do |link|
      level = link.curi.trimmed_path&.count("/")
      [nil, 1].include?(level) && !link.curi.trimmed_path&.match?(/\/\d\d\d\d(\/\d\d)?(\/\d\d)?$/)
    end
    are_any_feed_entries_top_level = feed_entry_links
      .to_a
      .any? { |entry_link| [nil, 1].include?(entry_link.curi.trimmed_path&.count("/")) }
    if are_any_feed_entries_top_level
      logger.info("Skipping phase 1 other links because some feed entries are top level")
    else
      phase1_others_count = 0
      filtered_start_page_other_links.each do |link|
        queryless_curi = canonical_uri_without_query(link.curi)
        next if guided_seen_queryless_curis_set.include?(queryless_curi)

        others_queue << link
        phase1_others_count += 1
      end
      logger.info("Phase 3 links from phase 1: #{phase1_others_count}")
    end

    result = guided_crawl_fetch_loop(
      [archives_queue, main_page_queue, others_queue], result, guided_seen_queryless_curis_set,
      archives_categories_state, feed_entry_links, feed_entry_curis_titles_map, feed_generator, curi_eq_cfg,
      allowed_hosts, 3, crawl_ctx, http_client, puppeteer_client, progress_logger, logger
    )
    if result
      logger.info("Phase 3 succeeded")
      return result
    end
  end

  logger.info("Pattern not detected")
  nil
end

def guided_crawl_fetch_loop(
  queues, initial_result, guided_seen_queryless_curis_set, archives_categories_state, feed_entry_links,
  feed_entry_curis_titles_map, feed_generator, curi_eq_cfg, allowed_hosts, phase_number, crawl_ctx,
  http_client, puppeteer_client, progress_logger, logger
)
  logger.info("Guided crawl loop started (phase #{phase_number})")

  sorted_results = initial_result ? [initial_result] : []
  archives_queue, main_page_queue = queues
  had_archives = !archives_queue.empty?
  archives_seen_count = archives_queue.length
  archives_processed_count = 0
  main_pages_seen_count = main_page_queue.length
  main_pages_processed_count = 0
  historical_matches_count = 0
  loop do
    active_queue_index = queues.index { |queue| !queue.empty? }
    break unless active_queue_index

    active_queue = queues[active_queue_index]
    if active_queue == archives_queue
      archives_processed_count += 1
    elsif active_queue == main_page_queue
      main_pages_processed_count += 1
    end

    link_or_page = active_queue.shift
    if link_or_page.is_a?(Link)
      link = link_or_page
      next if crawl_ctx.fetched_curis.include?(link.curi)

      page = crawl_request(link, false, crawl_ctx, http_client, progress_logger, logger)
      unless page.is_a?(Page) && page.document
        logger.info("Couldn't fetch link: #{page}")
        progress_logger.save_status
        next
      end
    elsif link_or_page.is_a?(Page)
      page = link_or_page
      link = to_canonical_link(page.fetch_uri.to_s, logger)
    else
      raise "Neither link nor page in the queue: #{link_or_page}"
    end

    progress_logger.save_status

    pptr_page = crawl_with_puppeteer_if_match(
      page, feed_entry_curis_titles_map, puppeteer_client, crawl_ctx, progress_logger, logger
    )
    progress_logger.save_status if pptr_page != page

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
        archives_seen_count += 1
        logger.info("Enqueueing archives link: #{page_link.curi}")
      elsif page_link.curi.trimmed_path&.match?(MAIN_PAGE_REGEX)
        guided_seen_queryless_curis_set << queryless_curi
        main_page_queue << page_link
        main_pages_seen_count += 1
        logger.info("Enqueueing main page link: #{page_link.curi}")
      end
    end

    page_curis_set = page_all_links
      .map(&:curi)
      .to_canonical_uri_set(curi_eq_cfg)
    page_results = try_extract_historical(
      link, pptr_page, page_all_links, page_curis_set, feed_entry_links, feed_entry_curis_titles_map,
      feed_generator, curi_eq_cfg, archives_categories_state, logger
    )
    page_results.each do |page_result|
      historical_matches_count += 1
      insert_sorted_result(page_result, sorted_results)
    end

    if had_archives && archives_queue.empty? && !sorted_results.empty?
      postprocessed_result = postprocess_results(
        sorted_results, feed_entry_links, feed_generator, curi_eq_cfg, crawl_ctx, http_client,
        progress_logger, logger
      )
      if postprocessed_result
        if postprocessed_result.count >= 21
          logger.info("Processed/seen: archives #{archives_processed_count}/#{archives_seen_count}, main pages #{main_pages_processed_count}/#{main_pages_seen_count}")
          logger.info("Historical matches: #{historical_matches_count}")
          logger.info("Guided crawl loop finished (phase #{phase_number}) after archives with best result of #{postprocessed_result.count} links")
          return postprocessed_result
        else
          logger.info("Best result after archives only has #{postprocessed_result.count} links. Checking others just in case")
          sorted_results.prepend(postprocessed_result)
        end
      end
    end
  end

  postprocessed_result = postprocess_results(
    sorted_results, feed_entry_links, feed_generator, curi_eq_cfg, crawl_ctx, http_client, progress_logger,
    logger
  )

  logger.info("Processed/seen: archives #{archives_processed_count}/#{archives_seen_count}, main pages #{main_pages_processed_count}/#{main_pages_seen_count}")
  logger.info("Historical matches: #{historical_matches_count}")

  if postprocessed_result
    logger.info("Guided crawl loop finished (phase #{phase_number}) with best result of #{postprocessed_result.count} links")
    return postprocessed_result
  end

  logger.info("Guided crawl loop finished (phase #{phase_number}), no result")
  nil
end

def try_extract_historical(
  page_link, page, page_links, page_curis_set, feed_entry_links, feed_entry_curis_titles_map, feed_generator,
  curi_eq_cfg, archives_categories_state, logger
)
  logger.info("Trying to extract historical from #{page.fetch_uri}")
  results = []

  archives_almost_match_threshold = get_archives_almost_match_threshold(feed_entry_links.length)
  extractions_by_masked_xpath_by_star_count = get_extractions_by_masked_xpath_by_star_count(
    page_links, feed_entry_links, feed_entry_curis_titles_map, curi_eq_cfg, archives_almost_match_threshold,
    logger
  )

  archives_results = try_extract_archives(
    page_link, page, page_links, page_curis_set, feed_entry_links, feed_entry_curis_titles_map,
    feed_generator, extractions_by_masked_xpath_by_star_count, archives_almost_match_threshold, curi_eq_cfg,
    logger
  )
  results.push(*archives_results)

  archives_categories_result = try_extract_archives_categories(
    page_link, page, page_curis_set, feed_entry_links, feed_entry_curis_titles_map,
    extractions_by_masked_xpath_by_star_count, archives_categories_state, curi_eq_cfg, logger
  )
  results << archives_categories_result if archives_categories_result

  page1_result = try_extract_page1(
    page_link, page, page_links, page_curis_set, feed_entry_links, feed_entry_curis_titles_map,
    feed_generator, extractions_by_masked_xpath_by_star_count, curi_eq_cfg, logger
  )
  results << page1_result if page1_result

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
  sorted_results, feed_entry_links, feed_generator, curi_eq_cfg, crawl_ctx, http_client, progress_logger,
  logger
)
  sorted_results_log = sorted_results.map { |result| print_result(result) }
  logger.info("Postprocessing #{sorted_results.length} results: #{sorted_results_log}")

  until sorted_results.empty?
    result = sorted_results.shift
    logger.info("Postprocessing #{print_result(result)}")
    if result.count
      pp_result = result
    else
      if result.is_a?(ArchivesMediumPinnedEntryResult)
        pp_result = postprocess_archives_medium_pinned_entry_result(
          result, feed_entry_links, curi_eq_cfg, crawl_ctx, http_client, progress_logger, logger
        )
      elsif result.is_a?(ArchivesShuffledResults)
        pp_result = postprocess_archives_shuffled_results(
          result, feed_entry_links, feed_generator, curi_eq_cfg, crawl_ctx, http_client, progress_logger,
          logger
        )
      elsif result.is_a?(ArchivesCategoriesResult)
        pp_result = postprocess_archives_categories_result(
          result, feed_entry_links, feed_generator, curi_eq_cfg, crawl_ctx, http_client, progress_logger,
          logger
        )
      elsif result.is_a?(Page1Result)
        # If page 1 result looks the best, check just page 2 in case it was a scam
        pp_result = postprocess_page1_result(
          result, feed_entry_links, curi_eq_cfg, crawl_ctx, http_client, progress_logger, logger
        )
      elsif result.is_a?(PartialPagedResult)
        pp_result = postprocess_paged_result(
          result, feed_entry_links, curi_eq_cfg, crawl_ctx, http_client, progress_logger, logger
        )
      else
        raise "Unknown result type: #{result}"
      end
    end

    unless pp_result
      logger.info("Postprocessing failed for #{result.main_link.url}, continuing")
      next
    end

    if sorted_results.empty? ||
      speculative_count_better_than(pp_result, sorted_results.first) ||
      (!pp_result.is_a?(PartialPagedResult) && speculative_count_equal(pp_result, sorted_results.first))

      if pp_result.is_a?(PartialPagedResult)
        pp_result = postprocess_paged_result(
          pp_result, feed_entry_links, curi_eq_cfg, crawl_ctx, http_client, progress_logger, logger
        )
        unless pp_result
          logger.info("Postprocessing failed for #{result.main_link.url}, continuing")
          next
        end
      end

      logger.info("Postprocessing succeeded")
      return pp_result
    end

    if pp_result.is_a?(PostprocessedResult) && !pp_result.is_matching_feed
      pp_not_matching_feed_log = ", not matching feed"
    else
      pp_not_matching_feed_log = ""
    end
    logger.info("Inserting back postprocessed #{print_result(pp_result)}#{pp_not_matching_feed_log}")
    insert_sorted_result(pp_result, sorted_results)
  end

  logger.info("Postprocessing failed")
  nil
end

PostprocessedResult = Struct.new(
  :main_link, :pattern, :links, :speculative_count, :count, :is_matching_feed, :post_categories, :extra,
  keyword_init: true
)

def print_result(result)
  "[#{result.class.name}, #{result.main_link.url}, #{result.speculative_count}]"
end

def postprocess_archives_medium_pinned_entry_result(
  medium_result, feed_entry_links, curi_eq_cfg, crawl_ctx, http_client, progress_logger, logger
)
  logger.info("Postprocess archives medium pinned entry result start")
  pinned_entry_page = crawl_request(
    medium_result.pinned_entry_link, false, crawl_ctx, http_client, progress_logger, logger
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
    logger.info("Couldn't sort links during postprocess archives medium pinned entry result finish")
    return nil
  end

  unless compare_with_feed(sorted_links, feed_entry_links, curi_eq_cfg, logger)
    logger.info("Postprocess archives medium pinned entry result not matching feed")
    return nil
  end

  logger.info("Postprocess archives medium pinned entry result finish")
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
  shuffled_results, feed_entry_links, feed_generator, curi_eq_cfg, crawl_ctx, http_client, progress_logger,
  logger
)
  logger.info("Postprocess archives shuffled results start")
  pages_by_canonical_url = {}
  sorted_tentative_results = shuffled_results.results.sort_by do |tentative_result|
    tentative_result.speculative_count
  end
  logger.info("Archives shuffled counts: #{sorted_tentative_results.map(&:speculative_count)}")

  best_result = nil
  sorted_tentative_results.each do |tentative_result|
    logger.info("Postprocessing archives shuffled result of #{tentative_result.speculative_count}")
    sorted_links = postprocess_sort_links_maybe_dates(
      tentative_result.links_maybe_dates, feed_entry_links, feed_generator, curi_eq_cfg,
      pages_by_canonical_url, crawl_ctx, http_client, progress_logger, logger
    )
    unless sorted_links
      logger.info("Postprocess archives shuffled results finish, iteration failed")
      return best_result
    end

    best_result = PostprocessedResult.new(
      main_link: shuffled_results.main_link,
      pattern: tentative_result.pattern,
      links: sorted_links.links,
      speculative_count: sorted_links.links.length,
      count: sorted_links.links.length,
      is_matching_feed: sorted_links.are_matching_feed,
      post_categories: tentative_result.post_categories,
      extra: tentative_result.extra + "<br>sort_date_source: #{sorted_links.date_source}<br>are_matching_feed: #{sorted_links.are_matching_feed}"
    )
  end

  logger.info("Postprocess archives shuffled results finish")
  best_result
end

def postprocess_archives_categories_result(
  archives_categories_result, feed_entry_links, feed_generator, curi_eq_cfg, crawl_ctx, http_client,
  progress_logger, logger
)
  logger.info("Postprocess archives categories results start")
  sorted_links = postprocess_sort_links_maybe_dates(
    archives_categories_result.links_maybe_dates, feed_entry_links, feed_generator, curi_eq_cfg, {},
    crawl_ctx, http_client, progress_logger, logger
  )
  unless sorted_links
    logger.info("Postprocess archives categories results failed")
    return nil
  end

  logger.info("Postprocess archives categories results finish")
  PostprocessedResult.new(
    main_link: archives_categories_result.main_link,
    pattern: archives_categories_result.pattern,
    links: sorted_links.links,
    speculative_count: sorted_links.links.length,
    count: sorted_links.links.length,
    is_matching_feed: sorted_links.are_matching_feed,
    extra: archives_categories_result.extra + "<br>sort_date_source: #{sorted_links.date_source}<br>are_matching_feed: #{sorted_links.are_matching_feed}"
  )
end

def postprocess_page1_result(
  page1_result, feed_entry_links, curi_eq_cfg, crawl_ctx, http_client, progress_logger, logger
)
  logger.info("Postprocess page1 result start")
  page2 = crawl_request(
    page1_result.link_to_page2, false, crawl_ctx, http_client, progress_logger, logger
  )
  progress_logger.log_and_save_postprocessing
  unless page2 && page2.is_a?(Page) && page2.document
    logger.info("Page 2 is not a page: #{page2}")
    return nil
  end

  paged_result = try_extract_page2(page2, page1_result.paged_state, feed_entry_links, curi_eq_cfg, logger)
  if paged_result
    progress_logger.log_and_save_count(zero_to_nil(paged_result.links.count(&:title)))
  end

  logger.info("Postprocess page1 result finish")
  paged_result
end

def postprocess_paged_result(
  paged_result, feed_entry_links, curi_eq_cfg, crawl_ctx, http_client, progress_logger, logger
)
  logger.info("Postprocess paged result start")
  while paged_result.is_a?(PartialPagedResult)
    progress_logger.log_and_save_count(zero_to_nil(paged_result.links.count(&:title)))
    page = crawl_request(
      paged_result.link_to_next_page, false, crawl_ctx, http_client, progress_logger, logger
    )
    progress_logger.log_and_save_postprocessing
    unless page && page.is_a?(Page) && page.document
      logger.info("Page #{paged_result.page_number} is not a page: #{page}")
      return nil
    end

    paged_result = try_extract_next_page(page, paged_result, feed_entry_links, curi_eq_cfg, logger)
  end

  if paged_result
    progress_logger.log_and_save_count(zero_to_nil(paged_result.links.count(&:title)))
    logger.info("Postprocess paged result finish")
  else
    progress_logger.log_and_save_count(nil)
    logger.info("Postprocess paged result failed")
  end

  paged_result
end

SortedLinks = Struct.new(:links, :are_matching_feed, :date_source)

def postprocess_sort_links_maybe_dates(
  links_maybe_dates, feed_entry_links, feed_generator, curi_eq_cfg, pages_by_canonical_url, crawl_ctx,
  http_client, progress_logger, logger
)
  logger.info("Postprocess sort links, maybe dates start")
  result_pages = []
  sort_state = nil
  links_with_dates, links_without_dates = links_maybe_dates.partition { |_, maybe_date| maybe_date }
  links_without_dates = links_without_dates.map(&:first)
  already_fetched_titles_count = links_with_dates.map(&:first).count(&:title)
  remaining_titles_count = links_with_dates.length - already_fetched_titles_count

  crawled_links, links_to_crawl = links_without_dates.partition do |link|
    pages_by_canonical_url.key?(link.curi.to_s)
  end

  crawled_links.each do |link|
    page = pages_by_canonical_url[link.curi.to_s]
    sort_state = historical_archives_sort_add(page, feed_generator, sort_state, logger)
    unless sort_state
      logger.info("Postprocess sort links, maybe dates failed during add already crawled")
      return nil
    end

    result_pages << page
  end

  links_to_crawl.each_with_index do |link, index|
    page = crawl_request(link, false, crawl_ctx, http_client, progress_logger, logger)
    unless page.is_a?(Page) && page.document
      progress_logger.log_and_save_postprocessing_reset_count
      logger.info("Couldn't fetch link during result postprocess: #{page}")
      return nil
    end

    sort_state = historical_archives_sort_add(page, feed_generator, sort_state, logger)
    unless sort_state
      progress_logger.log_and_save_postprocessing_reset_count
      logger.info("Postprocess sort links, maybe dates failed during add")
      return nil
    end

    fetched_count = already_fetched_titles_count + crawled_links.length + index + 1
    remaining_count = remaining_titles_count + links_to_crawl.length - index - 1
    progress_logger.log_and_save_postprocessing_counts(fetched_count, remaining_count)
    result_pages << page
    pages_by_canonical_url[page.curi.to_s] = page
  end

  sorted_links, date_source = historical_archives_sort_finish(
    links_with_dates, links_without_dates, sort_state, logger
  )
  unless sorted_links
    logger.info("Postprocess sort links, maybe dates failed during finish")
    return nil
  end

  are_matching_feed = compare_with_feed(sorted_links, feed_entry_links, curi_eq_cfg, logger)

  logger.info("Postprocess sort links, maybe dates finish")
  SortedLinks.new(sorted_links, are_matching_feed, date_source)
end

def canonical_uri_without_query(curi)
  CanonicalUri.new(curi.host, curi.port, curi.path, nil)
end

def compare_with_feed(sorted_links, feed_entry_links, curi_eq_cfg, logger)
  return true unless feed_entry_links.is_order_certain

  sorted_curis = sorted_links.map(&:curi)
  curis_set = sorted_curis.to_canonical_uri_set(curi_eq_cfg)
  present_feed_entry_links = feed_entry_links.filter_included(curis_set)
  is_matching_feed = present_feed_entry_links.sequence_match(sorted_curis, curi_eq_cfg)
  return true if is_matching_feed

  logger.info("Sorted links")
  sorted_links_trimmed_by_feed = sorted_curis.take(present_feed_entry_links.length).map(&:to_s)
  sorted_links_ellipsis = sorted_curis.length > present_feed_entry_links.length ? " ..." : ""
  logger.info("#{sorted_links_trimmed_by_feed}#{sorted_links_ellipsis}")
  logger.info("are not matching filtered feed:")
  logger.info(present_feed_entry_links)
  false
end

def fetch_missing_titles(
  links, feed_length, feed_entry_curis_titles_map, feed_generator, crawl_ctx, http_client, progress_logger,
  logger
)
  logger.info("Fetch missing titles start")
  present_titles_count = links.count(&:title)
  missing_titles_count = links.length - present_titles_count

  if missing_titles_count == 0
    logger.info("Fetch missing titles finish - no-op")
    crawl_ctx.title_requests_made = 0
    return links
  end

  if links.length <= feed_length
    links_with_feed_titles = []
    links.each do |link|
      if link.title
        links_with_feed_titles << link
        next
      end

      if feed_entry_curis_titles_map.include?(link.curi)
        feed_title = feed_entry_curis_titles_map[link.curi]
        links_with_feed_titles << link_set_title(link, feed_title)
        next
      end

      links_with_feed_titles << link
    end

    feed_present_titles_count = links_with_feed_titles.count(&:title)
    feed_missing_titles_count = links_with_feed_titles.length - feed_present_titles_count
    if missing_titles_count != feed_missing_titles_count
      logger.info("Filled #{missing_titles_count - feed_missing_titles_count}/#{missing_titles_count} missing titles from feeds")
    end

    if feed_missing_titles_count == 0
      logger.info("Fetch missing titles finish")
      crawl_ctx.title_requests_made = 0
      return links_with_feed_titles
    end
  else
    links_with_feed_titles = links
    feed_present_titles_count = present_titles_count
    feed_missing_titles_count = missing_titles_count
  end

  progress_logger.log_and_save_count(zero_to_nil(feed_present_titles_count))
  requests_made_start = crawl_ctx.requests_made

  links_with_titles = []
  page_titles = []
  fetched_titles_count = 0
  links_with_feed_titles.each do |link|
    if link.title
      links_with_titles << link
      next
    end

    # Always making a request may produce some duplicate requests, but hopefully not too many
    response = crawl_request(link, false, crawl_ctx, http_client, progress_logger, logger)
    if response.is_a?(Page) && response.document
      page_title = get_page_title(response, feed_generator)
      page_titles << page_title
      title = create_link_title(page_title, :page_title)
      links_with_titles << link_set_title(link, title)
    else
      logger.info("Couldn't fetch link title, going with url: #{response}")
      title = create_link_title(link.url, :page_url)
      links_with_titles << link_set_title(link, title)
    end

    fetched_titles_count += 1
    progress_logger.log_and_save_postprocessing_counts(
      feed_present_titles_count + fetched_titles_count, feed_missing_titles_count - fetched_titles_count
    )
  end

  crawl_ctx.title_requests_made = crawl_ctx.requests_made - requests_made_start

  if page_titles.empty?
    logger.info("Page titles are empty, skipped the prefix/suffix discovery")
    logger.info("Fetch missing titles finish")
    return links_with_titles
  end

  # Find out if page titles have a common prefix/suffix that needs to be removed
  first_page_title = page_titles.first
  #noinspection RubyNilAnalysis
  prefix_length = suffix_length = first_page_title.length
  page_titles.drop(1).each do |page_title|
    prefix_length = [page_title.length, prefix_length].min
    (0...prefix_length).each do |i|
      if page_title[i] != first_page_title[i]
        prefix_length = i
        break
      end
    end

    suffix_length = [page_title.length, suffix_length].min
    (1..suffix_length).each do |i|
      if page_title[-i] != first_page_title[-i]
        suffix_length = i - 1
        break
      end
    end
  end

  prefix = first_page_title[...prefix_length]
  suffix = suffix_length > 0 ? first_page_title[-suffix_length..] : ""
  if suffix.start_with?("...")
    suffix = suffix[3..]
    suffix_length -= 3
  elsif suffix.start_with?("…")
    suffix = suffix[1..]
    suffix_length -= 1
  end

  if prefix_length + suffix_length >= page_titles.map(&:length).min
    prefix_length = suffix_length = 0
    prefix = suffix = ""
  end

  def validate_first_link_title_prefix_suffix(
    first_link, prefix, suffix, links_count, feed_entry_curis_titles_map, feed_generator, crawl_ctx,
    http_client, progress_logger, logger
  )
    is_first_link_title_clean = first_link.title &&
      first_link.title.source != :feed &&
      feed_entry_curis_titles_map.include?(first_link.curi) &&
      first_link.title.equalized_value == feed_entry_curis_titles_map[first_link.curi].equalized_value

    unless is_first_link_title_clean
      logger.info("First link title is not clean, can't resolve page title prefixes/suffixes")
      return nil
    end

    progress_logger.log_and_save_postprocessing_counts(links_count, 1)
    response = crawl_request(first_link, false, crawl_ctx, http_client, progress_logger, logger)
    progress_logger.log_and_save_postprocessing_counts(links_count, 0)

    unless response.is_a?(Page) && response.document
      logger.info("Couldn't fetch first link title")
      return nil
    end

    first_link_page_title = get_page_title(response, feed_generator)
    unless first_link_page_title.start_with?(prefix)
      logger.info("First link prefix doesn't check out")
      return nil
    end
    unless first_link_page_title.end_with?(suffix)
      logger.info("First link suffix doesn't check out")
      return nil
    end

    logger.info("Checks out?")
    true
  end

  if prefix_length > 0 || suffix_length > 0
    logger.info("Found common prefix for page titles: #{prefix}") if prefix_length > 0
    logger.info("Found common suffix for page titles: #{suffix}") if suffix_length > 0
    if page_titles.length == links.length
      are_prefix_suffix_valid = true
    else
      first_link = links.first
      are_prefix_suffix_valid = validate_first_link_title_prefix_suffix(
        first_link, prefix, suffix, links.length, feed_entry_curis_titles_map, feed_generator, crawl_ctx,
        http_client, progress_logger, logger
      )
    end

    if are_prefix_suffix_valid
      links_with_titles.each do |link|
        next unless link.title.source == :page_title

        link.title = create_link_title(
          link.title.value[prefix_length..-suffix_length - 1], link.title.source
        )
      end
    end
  end

  logger.info("Fetch missing titles finish")
  links_with_titles
end

def zero_to_nil(count)
  count == 0 ? nil : count
end

def count_link_title_sources(links)
  counts_by_source = {}
  links.each do |link|
    source_str = link.title.source.to_s
    if counts_by_source.key?(source_str)
      counts_by_source[source_str] += 1
    else
      counts_by_source[source_str] = 1
    end
  end

  tokens = counts_by_source.map do |source_str, count|
    quote = source_str.start_with?("[") ? '' : '"'
    "#{quote}#{source_str}#{quote} => #{count}"
  end

  "{#{tokens.join(", ")}}"
end