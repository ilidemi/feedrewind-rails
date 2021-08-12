require 'set'
require_relative 'date_extraction'
require_relative 'historical_archives_sort'
require_relative 'historical_common'

ArchivesResult = Struct.new(:main_result, :count, :tentative_better_results)

def get_archives_almost_match_threshold(feed_length)
  if feed_length <= 3
    feed_length
  elsif feed_length <= 7
    feed_length - 1
  elsif feed_length <= 25
    feed_length - 2
  elsif feed_length <= 62
    feed_length - 3
  else
    feed_length - 7
  end
end

def try_extract_archives(
  page, page_links, page_curis_set, feed_entry_links, feed_entry_curis_set, feed_generator,
  extractions_by_masked_xpath_by_star_count, almost_match_threshold, curi_eq_cfg, logger
)
  return nil unless feed_entry_links.count_included(page_curis_set) >= almost_match_threshold

  logger.log("Possible archives page: #{page.curi}")

  main_result = nil
  min_links_count = 1

  sorted_fewer_stars_curis = nil
  sorted_fewer_stars_have_dates = nil
  extractions_by_masked_xpath_by_star_count.each do |star_count, extractions_by_masked_xpath|
    sorted_result = try_extract_sorted(
      extractions_by_masked_xpath, feed_entry_links, curi_eq_cfg, nil, star_count,
      sorted_fewer_stars_curis, sorted_fewer_stars_have_dates, min_links_count, logger
    )
    if sorted_result
      main_result = sorted_result
      min_links_count = sorted_result.count + 1
      sorted_fewer_stars_curis = sorted_result.links.map(&:curi)
      sorted_fewer_stars_have_dates = sorted_result.has_dates
    end
  end

  if feed_entry_links.length < 3
    logger.log("Skipping sorted match with highlighted first link because the feed is small (#{feed_entry_links.length})")
  else
    sorted1_fewer_stars_curis = nil
    extractions_by_masked_xpath_by_star_count.each do |star_count, extractions_by_masked_xpath|
      sorted1_result = try_extract_sorted_highlight_first_link(
        extractions_by_masked_xpath, feed_entry_links, curi_eq_cfg, page_curis_set, star_count,
        sorted1_fewer_stars_curis, min_links_count, logger
      )
      if sorted1_result
        main_result = sorted1_result
        min_links_count = sorted1_result.count + 1
        sorted1_fewer_stars_curis = sorted1_result.links.map(&:curi)
      end
    end
  end

  medium_pinned_entry_result = try_extract_medium_with_pinned_entry(
    extractions_by_masked_xpath_by_star_count[1], feed_entry_links, curi_eq_cfg, feed_generator, page_links,
    min_links_count, logger
  )
  if medium_pinned_entry_result
    main_result = medium_pinned_entry_result
    min_links_count = medium_pinned_entry_result.count + 1
  end

  sorted_2xpaths_fewer_stars_curis = nil
  extractions_by_masked_xpath_by_star_count.each do |star_count, extractions_by_masked_xpath|
    sorted_2xpaths_result = try_extract_sorted_2xpaths(
      extractions_by_masked_xpath_by_star_count[1], extractions_by_masked_xpath, feed_entry_links,
      curi_eq_cfg, star_count, sorted_2xpaths_fewer_stars_curis, min_links_count, logger
    )
    if sorted_2xpaths_result
      main_result = sorted_2xpaths_result
      min_links_count = sorted_2xpaths_result.count + 1
      sorted_2xpaths_fewer_stars_curis = sorted_2xpaths_result.links.map(&:curi)
    end
  end

  if feed_entry_links.length < min_links_count
    logger.log("Skipping almost feed match because min links count is already greater (#{min_links_count} > #{feed_entry_links.length})")
  else
    almost_feed_fewer_stars_curis = nil
    extractions_by_masked_xpath_by_star_count.each do |star_count, extractions_by_masked_xpath|
      almost_feed_result = try_extract_almost_matching_feed(
        extractions_by_masked_xpath, feed_entry_links, feed_entry_curis_set, curi_eq_cfg,
        almost_match_threshold, star_count, almost_feed_fewer_stars_curis, logger
      )
      if almost_feed_result
        main_result = almost_feed_result
        min_links_count = almost_feed_result.count + 1
        almost_feed_fewer_stars_curis = almost_feed_result.links.map(&:curi)
      end
    end
  end

  tentative_better_results = []

  if main_result.is_a?(SortedResult) && main_result.has_dates
    logger.log("Skipping shuffled match because there's already a sorted result with dates")
  else
    extractions_by_masked_xpath_by_star_count.each do |star_count, extractions_by_masked_xpath|
      shuffled_result = try_extract_shuffled(
        extractions_by_masked_xpath, feed_entry_links, curi_eq_cfg, nil, star_count,
        min_links_count, logger
      )
      if shuffled_result
        tentative_better_results << shuffled_result
        min_links_count = shuffled_result.count + 1
      end
    end
  end

  sorted_almost_fewer_stars_curis = nil
  sorted_almost_fewer_stars_have_dates = nil
  extractions_by_masked_xpath_by_star_count.each do |star_count, extractions_by_masked_xpath|
    sorted_almost_result = try_extract_sorted(
      extractions_by_masked_xpath, feed_entry_links, curi_eq_cfg, almost_match_threshold, star_count,
      sorted_almost_fewer_stars_curis, sorted_almost_fewer_stars_have_dates,
      min_links_count, logger
    )
    if sorted_almost_result
      main_result = sorted_almost_result
      min_links_count = sorted_almost_result.count + 1
      sorted_almost_fewer_stars_curis = sorted_almost_result.links.map(&:curi)
      sorted_almost_fewer_stars_have_dates = sorted_almost_result.has_dates
    end
  end

  if main_result.is_a?(SortedResult) && main_result.has_dates
    logger.log("Skipping shuffled_almost match because there's already a sorted result with dates")
  else
    extractions_by_masked_xpath_by_star_count.each do |star_count, extractions_by_masked_xpath|
      shuffled_almost_result = try_extract_shuffled(
        extractions_by_masked_xpath, feed_entry_links, curi_eq_cfg, almost_match_threshold, star_count,
        min_links_count, logger
      )
      if shuffled_almost_result
        tentative_better_results << shuffled_almost_result
        min_links_count = shuffled_almost_result.count + 1
      end
    end
  end

  long_feed_result = try_extract_long_feed(
    feed_entry_links, page_curis_set, min_links_count, logger
  )
  if long_feed_result
    main_result = long_feed_result
    min_links_count = long_feed_result.count + 1
  end

  ArchivesResult.new(main_result, main_result&.count, tentative_better_results)
end

SortedResult = Struct.new(:pattern, :links, :count, :has_dates, :extra, keyword_init: true)

def try_extract_sorted(
  extractions_by_masked_xpath, feed_entry_links, curi_eq_cfg, almost_match_threshold, star_count,
  fewer_stars_curis, fewer_stars_have_dates, min_links_count, logger
)
  is_almost = !!almost_match_threshold
  almost_suffix = is_almost ? "_almost" : ""
  logger.log("Trying sorted#{almost_suffix} match with #{star_count} stars")

  best_xpath = nil
  best_links = nil
  best_has_dates = nil
  best_pattern = nil
  extractions_by_masked_xpath.each do |masked_xpath, extraction|
    links_extraction = extraction.links_extraction
    links = links_extraction.links
    curis = links_extraction.curis
    curis_set = links_extraction.curis_set
    dates = extraction.markup_dates_extraction.dates

    next if best_links && best_links.length >= links.length
    next if fewer_stars_have_dates && !dates
    next unless links.length >= feed_entry_links.length
    next unless links.length >= min_links_count

    log_lines = extraction.log_lines.clone
    if is_almost
      target_feed_entry_links = feed_entry_links.filter_included(curis_set)
      next unless target_feed_entry_links.length < feed_entry_links.length
      next unless target_feed_entry_links.length >= almost_match_threshold
      log_lines << "almost feed match #{target_feed_entry_links.length}/#{feed_entry_links.length}"
    else
      next unless feed_entry_links.all_included?(curis_set)
      target_feed_entry_links = feed_entry_links
    end

    is_matching_feed = target_feed_entry_links.sequence_match?(curis, curi_eq_cfg)
    is_matching_fewer_stars_links = fewer_stars_curis &&
      curis[...fewer_stars_curis.length]
        .zip(fewer_stars_curis)
        .all? do |xpath_curi, fewer_stars_curi|
        canonical_uri_equal?(xpath_curi, fewer_stars_curi, curi_eq_cfg)
      end
    if extraction.markup_dates_extraction.are_sorted != false &&
      is_matching_feed &&
      !links_extraction.has_duplicates &&
      (!fewer_stars_curis || is_matching_fewer_stars_links)

      best_xpath = masked_xpath
      best_links = links
      best_has_dates = !!dates
      best_pattern = "archives#{almost_suffix}"
      log_lines << "has dates" if best_has_dates
      logger.log("Masked xpath is good: #{masked_xpath}#{join_log_lines(log_lines)} (#{links.length} links)")
      next
    end

    reversed_links = links.reverse
    reversed_curis = curis.reverse
    is_reversed_matching_feed = target_feed_entry_links.sequence_match?(reversed_curis, curi_eq_cfg)
    is_reversed_matching_fewer_stars_links_prefix = fewer_stars_curis &&
      reversed_curis[...fewer_stars_curis.length]
        .zip(fewer_stars_curis)
        .all? do |xpath_curi, fewer_stars_curi|
        canonical_uri_equal?(xpath_curi, fewer_stars_curi, curi_eq_cfg)
      end
    is_reversed_matching_fewer_stars_links_suffix = fewer_stars_curis &&
      reversed_curis[-fewer_stars_curis.length..]
        .zip(fewer_stars_curis)
        .all? do |xpath_curi, fewer_stars_curi|
        canonical_uri_equal?(xpath_curi, fewer_stars_curi, curi_eq_cfg)
      end
    if extraction.markup_dates_extraction.are_reverse_sorted != false &&
      is_reversed_matching_feed &&
      !links_extraction.has_duplicates &&
      (!fewer_stars_curis ||
        is_reversed_matching_fewer_stars_links_prefix ||
        is_reversed_matching_fewer_stars_links_suffix)

      best_xpath = masked_xpath
      best_links = reversed_links
      best_has_dates = !!dates
      best_pattern = "archives#{almost_suffix}"
      log_lines << "has dates" if best_has_dates
      logger.log("Masked xpath is good in reverse order: #{masked_xpath}#{join_log_lines(log_lines)} (#{reversed_links.length} links)")
      next
    end

    if dates
      unique_links_dates = []
      curis_set_by_date = {}
      links.zip(dates).each do |link, date|
        unless curis_set_by_date.key?(date)
          curis_set_by_date[date] = CanonicalUriSet.new([], curi_eq_cfg)
        end

        unless curis_set_by_date[date].include?(link.curi)
          unique_links_dates << [link, date]
          curis_set_by_date[date] << link.curi
        end
      end

      if unique_links_dates.length != curis_set.length
        canonical_urls_dates = curis
          .zip(dates)
          .map { |curi, date| [curi.to_s, date.strftime("%Y-%m-%d")] }
        logger.log("Masked xpath #{masked_xpath} has all links with dates but also duplicates with conflicting dates: #{canonical_urls_dates}")
        next
      end

      sorted_links_dates = sort_links_dates(unique_links_dates)
      sorted_links = sorted_links_dates.map { |link_date| link_date[0] }
      sorted_curis = sorted_links.map(&:curi)
      is_sorted_matching_feed = target_feed_entry_links.sequence_match?(sorted_curis, curi_eq_cfg)
      unless is_sorted_matching_feed
        logger.log("Masked xpath #{masked_xpath} has all links with dates but doesn't match feed after sorting")
        sorted_masked_xpath_links_dates_log = sorted_links_dates
          .map { |link_date| [link_date[0].curi.to_s, link_date[1].strftime("%Y-%m-%d")] }
        logger.log("Masked xpath links with dates: #{sorted_masked_xpath_links_dates_log}")
        logger.log("Feed links: #{target_feed_entry_links}")
        next
      end

      # Don't compare with fewer stars canonical urls
      # If it's two stars by category, categories are interspersed and have dates, but one category matches
      # feed, dates are still a good signal to merge the categories

      best_xpath = masked_xpath
      best_links = sorted_links
      best_has_dates = true
      best_pattern = "archives_shuffled#{almost_suffix}"
      log_lines_str = join_log_lines(log_lines)
      newest_date = sorted_links_dates.first[1]
      oldest_date = sorted_links_dates.last[1]
      logger.log("Masked xpath is good sorted by date: #{masked_xpath}#{log_lines_str} (#{sorted_links.length} links from #{oldest_date} to #{newest_date})")
      next
    end
  end

  if best_links
    SortedResult.new(
      pattern: best_pattern,
      links: best_links,
      count: best_links.length,
      has_dates: best_has_dates,
      extra: "<br>xpath: #{best_xpath}"
    )
  else
    logger.log("No sorted match with #{star_count} stars")
    nil
  end
end

def join_log_lines(log_lines)
  if log_lines.empty?
    ""
  else
    " (#{log_lines.join(", ")})"
  end
end

def try_extract_sorted_highlight_first_link(
  extractions_by_masked_xpath, feed_entry_links, curi_eq_cfg, page_curis_set, star_count, fewer_stars_curis,
  min_links_count, logger
)
  logger.log("Trying sorted match with highlighted first link and #{star_count} stars")

  best_xpath = nil
  best_first_link = nil
  best_links = nil
  extractions_by_masked_xpath.each do |masked_xpath, extraction|
    links_extraction = extraction.links_extraction
    links = links_extraction.links
    curis = links_extraction.curis

    next if best_links && best_links.length >= links.length
    next unless links.length >= feed_entry_links.length - 1
    next unless links.length >= min_links_count - 1

    is_matching_feed, first_link = feed_entry_links.sequence_match_except_first?(curis, curi_eq_cfg)
    is_matching_fewer_stars_links = fewer_stars_curis &&
      fewer_stars_curis[1..]
        .zip(curis[...fewer_stars_curis.length - 1])
        .all? do |xpath_uri, fewer_stars_uri|
        canonical_uri_equal?(xpath_uri, fewer_stars_uri, curi_eq_cfg)
      end
    if is_matching_feed &&
      page_curis_set.include?(first_link.curi) &&
      (is_matching_fewer_stars_links || !fewer_stars_curis)

      best_xpath = masked_xpath
      best_first_link = first_link
      best_links = links
      logger.log("Masked xpath is good: #{masked_xpath}#{join_log_lines(extraction.log_lines)} (1 + #{links.length} links)")
      next
    end
  end

  if best_links && best_first_link
    SortedResult.new(
      pattern: "archives_2xpaths",
      links: [best_first_link] + best_links,
      count: 1 + best_links.length,
      has_dates: nil,
      extra: "<br>counts: 1 + #{best_links.length}<br>prefix_xpath: #{best_first_link.xpath}<br>suffix_xpath: #{best_xpath}",
    )
  else
    logger.log("No sorted match with highlighted first link and #{star_count} stars")
    nil
  end
end

MediumWithPinnedEntryResult = Struct.new(
  :pattern, :pinned_entry_link, :other_links_dates, :count, :extra, keyword_init: true
)

def try_extract_medium_with_pinned_entry(
  extractions_by_masked_xpath, feed_entry_links, curi_eq_cfg, feed_generator, page_links, min_links_count,
  logger
)
  logger.log("Trying medium match with pinned entry")

  unless feed_generator == :medium
    logger.log("Feed generator is not Medium")
    return nil
  end

  extractions_by_masked_xpath.each do |masked_xpath, extraction|

    links_extraction = extraction.links_extraction
    links = links_extraction.links
    canonical_uris_set = links_extraction.curis_set
    medium_markup_dates = extraction.medium_markup_dates

    next unless links.length >= feed_entry_links.length - 1
    next unless links.length >= min_links_count - 1
    next unless medium_markup_dates

    feed_links_not_matching = feed_entry_links
      .to_a
      .filter { |entry_link| !canonical_uris_set.include?(entry_link.curi) }
    next unless feed_links_not_matching.length == 1

    pinned_entry_link = page_links.find do |page_link|
      canonical_uri_equal?(page_link.curi, feed_links_not_matching.first.curi, curi_eq_cfg)
    end
    next unless pinned_entry_link

    other_links_dates = links.zip(medium_markup_dates)

    logger.log("Masked xpath is good with medium pinned entry: #{masked_xpath}#{join_log_lines(extraction.log_lines)} (1 + #{other_links_dates.length} links)")
    return MediumWithPinnedEntryResult.new(
      pattern: "archives_shuffled_2xpaths",
      pinned_entry_link: pinned_entry_link,
      other_links_dates: other_links_dates,
      count: 1 + other_links_dates.length,
      extra: "<br>counts: 1 + #{links.length}<br>prefix_xpath: #{pinned_entry_link.xpath}<br>suffix_xpath: #{masked_xpath}",
    )
  end

  logger.log("No medium match with pinned entry")
  nil
end

def try_extract_sorted_2xpaths(
  prefix_extractions_by_masked_xpath, suffix_extractions_by_masked_xpath, feed_entry_links, curi_eq_cfg,
  star_count, fewer_stars_curis, min_links_count, logger
)
  logger.log("Trying sorted match with 1+#{star_count} stars")

  feed_prefix_xpaths_by_length = {}
  prefix_extractions_by_masked_xpath.each do |masked_xpath, extraction|
    links = extraction.links_extraction.links
    curis = extraction.links_extraction.curis
    next if links.length >= feed_entry_links.length

    is_matching_feed = feed_entry_links.sequence_match?(curis, curi_eq_cfg)
    next unless is_matching_feed

    unless feed_prefix_xpaths_by_length.key?(links.length)
      feed_prefix_xpaths_by_length[links.length] = []
    end
    feed_prefix_xpaths_by_length[links.length] << masked_xpath
  end

  best_links = nil
  best_prefix_xpath = nil
  best_suffix_xpath = nil
  best_prefix_count = nil
  best_suffix_count = nil

  suffix_extractions_by_masked_xpath.each do |masked_suffix_xpath, suffix_extraction|
    suffix_links_extraction = suffix_extraction.links_extraction
    suffix_links = suffix_links_extraction.links
    suffix_curis = suffix_links_extraction.curis

    is_suffix, target_prefix_length = feed_entry_links.sequence_is_suffix?(suffix_curis, curi_eq_cfg)
    next unless is_suffix
    next unless target_prefix_length + suffix_links.length >= feed_entry_links.length
    next unless feed_prefix_xpaths_by_length.key?(target_prefix_length)

    total_length = target_prefix_length + suffix_links.length
    next unless total_length >= min_links_count
    next if best_links && total_length <= best_links.length

    masked_prefix_xpath = feed_prefix_xpaths_by_length[target_prefix_length][0]
    prefix_extraction = prefix_extractions_by_masked_xpath[masked_prefix_xpath]
    prefix_links = prefix_extraction.links_extraction.links

    # Ensure the first suffix link appears on the page after the last prefix link
    # Find the lowest common parent and see if prefix parent comes before suffix parent
    last_prefix_link = prefix_links.last
    first_suffix_link = suffix_links.first
    # Link can't be a parent of another link. Not actually expecting that but just in case
    next if last_prefix_link.element == first_suffix_link.element.parent ||
      first_suffix_link.element == last_prefix_link.element.parent
    prefix_parent_id_to_self_and_child = {}
    current_prefix_element = last_prefix_link.element
    while current_prefix_element.element? do
      #noinspection RubyResolve
      prefix_parent_id_to_self_and_child[current_prefix_element.parent.pointer_id] =
        [current_prefix_element.parent, current_prefix_element]
      current_prefix_element = current_prefix_element.parent
    end
    top_suffix_element = first_suffix_link.element
    #noinspection RubyResolve
    while top_suffix_element.element? &&
      !prefix_parent_id_to_self_and_child.key?(top_suffix_element.parent.pointer_id) do

      top_suffix_element = top_suffix_element.parent
    end
    #noinspection RubyResolve
    common_parent, top_prefix_element =
      prefix_parent_id_to_self_and_child[top_suffix_element.parent.pointer_id]
    is_last_prefix_before_first_suffix = nil
    common_parent.children.each do |child|
      if child == top_prefix_element
        is_last_prefix_before_first_suffix = true
        break
      end
      if child == top_suffix_element
        is_last_prefix_before_first_suffix = false
        break
      end
    end
    next unless is_last_prefix_before_first_suffix

    logger.log("Found partition with two xpaths: #{target_prefix_length} + #{suffix_links.length}")
    logger.log("Prefix xpath: #{masked_prefix_xpath}#{join_log_lines(prefix_extraction.log_lines)}")
    logger.log("Suffix xpath: #{masked_suffix_xpath}#{join_log_lines(suffix_extraction.log_lines)}")

    combined_links = prefix_links + suffix_links
    combined_curis = combined_links.map(&:curi)
    combined_curis_set = combined_curis.to_canonical_uri_set(curi_eq_cfg)
    if combined_curis.length != combined_curis_set.length
      logger.log("Combination has all feed links but also duplicates: #{combined_curis.map(&:to_s)}")
      next
    end

    is_matching_prev_archives_links = !fewer_stars_curis ||
      fewer_stars_curis
        .zip(combined_curis[...fewer_stars_curis.length])
        .all? do |xpath_curi, fewer_stars_curi|
        canonical_uri_equal?(xpath_curi, fewer_stars_curi, curi_eq_cfg)
      end
    unless is_matching_prev_archives_links
      logger.log("Combination doesn't match previous archives links")
      next
    end

    best_links = combined_links
    best_prefix_xpath = masked_prefix_xpath
    best_suffix_xpath = masked_suffix_xpath
    best_prefix_count = target_prefix_length
    best_suffix_count = suffix_links.length
    logger.log("Combination is good (#{combined_links.length} links)")
  end

  if best_links
    SortedResult.new(
      pattern: "archives_2xpaths",
      links: best_links,
      count: best_links.length,
      extra: "<br>star_count: 1 + #{star_count}<br>counts: #{best_prefix_count} + #{best_suffix_count}<br>prefix_xpath: #{best_prefix_xpath}<br>suffix_xpath: #{best_suffix_xpath}"
    )
  else
    logger.log("No sorted match with 1+#{star_count} stars")
    nil
  end
end

def try_extract_almost_matching_feed(
  extractions_by_masked_xpath, feed_entry_links, feed_entry_curis_set, curi_eq_cfg, almost_match_threshold,
  star_count, fewer_stars_curis, logger
)
  logger.log("Trying almost feed match with #{star_count} stars")

  best_links = nil
  best_xpath = nil

  extractions_by_masked_xpath.each do |masked_xpath, extraction|
    links_extraction = extraction.links_extraction
    links = links_extraction.links
    curis = links_extraction.curis
    curis_set = links_extraction.curis_set

    next if best_links && best_links.length >= links.length
    next unless links.length < feed_entry_links.length
    next unless links.length >= almost_match_threshold
    next unless feed_entry_links.count_included(curis_set) >= almost_match_threshold
    next unless curis.all? { |curi| feed_entry_curis_set.include?(curi) }

    is_matching_fewer_stars_links = fewer_stars_curis &&
      curis[...fewer_stars_curis.length]
        .zip(fewer_stars_curis)
        .all? do |xpath_curi, fewer_stars_curi|
        canonical_uri_equal?(xpath_curi, fewer_stars_curi, curi_eq_cfg)
      end
    next unless !fewer_stars_curis || is_matching_fewer_stars_links

    best_links = links
    best_xpath = masked_xpath
    logger.log("Masked xpath almost matches feed: #{masked_xpath}#{join_log_lines(extraction.log_lines)} (#{links.length}/#{feed_entry_links.length} links)")
  end

  if best_links
    SortedResult.new(
      pattern: "feed",
      links: feed_entry_links.to_a,
      count: feed_entry_links.length,
      extra: "<br>almost_match: #{best_links.length}/#{feed_entry_links.length}<br>xpath:#{best_xpath}"
    )
  else
    logger.log("No almost feed match with #{star_count} stars")
    nil
  end
end

ShuffledResult = Struct.new(:pattern, :links_maybe_dates, :count, :extra, keyword_init: true)

def try_extract_shuffled(
  extractions_by_masked_xpath, feed_entry_links, curi_eq_cfg, almost_match_threshold, star_count,
  min_links_count, logger
)
  is_almost = !!almost_match_threshold
  almost_suffix = is_almost ? "_almost" : ""
  logger.log("Trying shuffled#{almost_suffix} match with #{star_count} stars")

  best_links_maybe_dates = nil
  best_xpath = nil

  extractions_by_masked_xpath.each do |masked_xpath, extraction|
    links_extraction = extraction.links_extraction
    links = links_extraction.links
    curis = links_extraction.curis
    curis_set = links_extraction.curis_set
    maybe_url_dates = extraction.maybe_url_dates

    next if best_links_maybe_dates && best_links_maybe_dates.length >= links.length
    next unless links.length >= feed_entry_links.length
    next unless links.length >= min_links_count

    log_lines = extraction.log_lines.clone
    if is_almost
      target_feed_entry_links = feed_entry_links.filter_included(curis_set)
      next unless target_feed_entry_links.length < feed_entry_links.length
      next unless target_feed_entry_links.length >= almost_match_threshold
      log_lines << "almost feed match #{target_feed_entry_links.length}/#{feed_entry_links.length}"
    else
      next unless feed_entry_links.all_included?(curis_set)
    end

    links_maybe_url_dates = links.zip(maybe_url_dates)
    if curis.length != curis_set.length
      dedup_links_maybe_dates = []
      dedup_curis_set = CanonicalUriSet.new([], curi_eq_cfg)
      links_maybe_url_dates.each do |link, maybe_url_date|
        next if dedup_curis_set.include?(link.curi)

        dedup_links_maybe_dates << [link, maybe_url_date]
        dedup_curis_set << link.curi
      end
    else
      dedup_links_maybe_dates = links_maybe_url_dates
    end

    best_links_maybe_dates = dedup_links_maybe_dates
    best_xpath = masked_xpath
    if links.length > dedup_links_maybe_dates.length
      log_lines << "dedup #{links.length} -> #{dedup_links_maybe_dates.length}"
    end
    logger.log("Masked xpath is good but shuffled: #{masked_xpath}#{join_log_lines(log_lines)} (#{dedup_links_maybe_dates.length} links)")
  end

  if best_links_maybe_dates
    dates_present = best_links_maybe_dates.count { |_, date| date }
    ShuffledResult.new(
      pattern: "archives_shuffled#{almost_suffix}",
      links_maybe_dates: best_links_maybe_dates,
      count: best_links_maybe_dates.count,
      extra: "<br>xpath: #{best_xpath}<br>dates_present:#{dates_present}/#{best_links_maybe_dates.length}"
    )
  else
    logger.log("No shuffled match with #{star_count} stars")
    nil
  end
end

LongFeedResult = Struct.new(:pattern, :links, :count, :extra, keyword_init: true)

def try_extract_long_feed(feed_entry_links, page_curis_set, min_links_count, logger)
  logger.log("Trying long feed match")

  if feed_entry_links.length >= 31 &&
    feed_entry_links.length > min_links_count &&
    feed_entry_links.all_included?(page_curis_set)

    logger.log("Long feed is matching (#{feed_entry_links.length} links)")
    LongFeedResult.new(
      pattern: "long_feed",
      links: feed_entry_links.to_a,
      count: feed_entry_links.length,
      extra: ""
    )
  else
    logger.log("No long feed match")
    nil
  end
end