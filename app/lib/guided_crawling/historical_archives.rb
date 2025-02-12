require 'set'
require_relative 'blog_post_categories'
require_relative 'date_extraction'
require_relative 'hardcoded_blogs'
require_relative 'historical_archives_sort'
require_relative 'historical_common'

ArchivesSortedResult = Struct.new(
  :main_link, :pattern, :links, :speculative_count, :count, :has_dates, :post_categories, :extra,
  keyword_init: true
)
ArchivesMediumPinnedEntryResult = Struct.new(
  :main_link, :pattern, :pinned_entry_link, :other_links_dates, :speculative_count, :count, :extra,
  keyword_init: true
)
LongFeedResult = Struct.new(
  :main_link, :pattern, :links, :speculative_count, :count, :post_categories, :extra, keyword_init: true
)
ArchivesShuffledResults = Struct.new(:main_link, :results, :speculative_count, :count, keyword_init: true)

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
  page_link, page, page_links, page_curis_set, feed_entry_links, feed_entry_curis_titles_map, feed_generator,
  extractions_by_masked_xpath_by_star_count, almost_match_threshold, curi_eq_cfg, logger
)
  return [] unless feed_entry_links.count_included(page_curis_set) >= almost_match_threshold

  if HardcodedBlogs::is_match(page_link, HardcodedBlogs::CRYPTOGRAPHY_ENGINEERING_ALL, curi_eq_cfg)
    logger.info("Skipping archives for Cryptography Engineering to pick up categories from paged")
    return []
  end

  logger.info("Possible archives page: #{page.curi}")

  main_result = nil
  min_links_count = 1

  if HardcodedBlogs::is_match(page_link, HardcodedBlogs::JULIA_EVANS, curi_eq_cfg)
    logger.info("Extracting archives for Julia Evans")
    jvns_star_count = 2
    jvns_extractions_by_masked_xpath = extractions_by_masked_xpath_by_star_count[jvns_star_count]
    shuffled_result = try_extract_shuffled(
      page, jvns_extractions_by_masked_xpath, feed_entry_links, curi_eq_cfg, nil, jvns_star_count,
      min_links_count, page_link, logger
    )
    if shuffled_result
      return [ArchivesShuffledResults.new(
        main_link: page_link,
        results: [shuffled_result],
        speculative_count: shuffled_result.speculative_count,
        count: nil
      )]
    else
      logger.error("Couldn't extract archives for Julia Evans")
    end
  end

  sorted_fewer_stars_curis = nil
  sorted_fewer_stars_have_dates = nil
  extractions_by_masked_xpath_by_star_count.each do |star_count, extractions_by_masked_xpath|
    sorted_result = try_extract_sorted(
      extractions_by_masked_xpath, feed_entry_links, curi_eq_cfg, nil, star_count, sorted_fewer_stars_curis,
      sorted_fewer_stars_have_dates, min_links_count, page_link, logger
    )
    if sorted_result
      main_result = sorted_result
      min_links_count = sorted_result.speculative_count + 1
      sorted_fewer_stars_curis = sorted_result.links.map(&:curi)
      sorted_fewer_stars_have_dates = sorted_result.has_dates
    end
  end

  if feed_entry_links.length < 3
    logger.info("Skipping sorted match with highlighted first link because the feed is small (#{feed_entry_links.length})")
  else
    sorted1_fewer_stars_curis = nil
    extractions_by_masked_xpath_by_star_count.each do |star_count, extractions_by_masked_xpath|
      sorted1_result = try_extract_sorted_highlight_first_link(
        extractions_by_masked_xpath, feed_entry_links, feed_entry_curis_titles_map, curi_eq_cfg,
        page_curis_set, star_count, sorted1_fewer_stars_curis, min_links_count, page_link, logger
      )
      if sorted1_result
        main_result = sorted1_result
        min_links_count = sorted1_result.speculative_count + 1
        sorted1_fewer_stars_curis = sorted1_result.links.map(&:curi)
      end
    end
  end

  medium_pinned_entry_result = try_extract_medium_pinned_entry(
    extractions_by_masked_xpath_by_star_count[1], feed_entry_links, curi_eq_cfg, feed_generator, page_links,
    min_links_count, page_link, logger
  )
  if medium_pinned_entry_result
    # Medium with pinned entry is a very specific match
    return [medium_pinned_entry_result]
  end

  sorted_2xpaths_fewer_stars_curis = nil
  extractions_by_masked_xpath_by_star_count.each do |star_count, extractions_by_masked_xpath|
    sorted_2xpaths_result = try_extract_sorted_2xpaths(
      extractions_by_masked_xpath_by_star_count[1], extractions_by_masked_xpath, feed_entry_links,
      curi_eq_cfg, star_count, sorted_2xpaths_fewer_stars_curis, min_links_count, page_link, logger
    )
    if sorted_2xpaths_result
      main_result = sorted_2xpaths_result
      min_links_count = sorted_2xpaths_result.speculative_count + 1
      sorted_2xpaths_fewer_stars_curis = sorted_2xpaths_result.links.map(&:curi)
    end
  end

  if feed_entry_links.length < min_links_count
    logger.info("Skipping almost feed match because min links count is already greater (#{min_links_count} > #{feed_entry_links.length})")
  else
    almost_feed_fewer_stars_curis = nil
    extractions_by_masked_xpath_by_star_count.each do |star_count, extractions_by_masked_xpath|
      almost_feed_result = try_extract_almost_matching_feed(
        extractions_by_masked_xpath, feed_entry_links, feed_entry_curis_titles_map, curi_eq_cfg,
        almost_match_threshold, star_count, almost_feed_fewer_stars_curis, page_link, logger
      )
      if almost_feed_result
        main_result = almost_feed_result
        min_links_count = almost_feed_result.speculative_count + 1
        almost_feed_fewer_stars_curis = almost_feed_result.links.map(&:curi)
      end
    end
  end

  tentative_better_results = []

  if main_result.is_a?(ArchivesSortedResult) && main_result.has_dates
    logger.info("Skipping shuffled match because there's already a sorted result with dates")
  else
    extractions_by_masked_xpath_by_star_count.each do |star_count, extractions_by_masked_xpath|
      shuffled_result = try_extract_shuffled(
        page, extractions_by_masked_xpath, feed_entry_links, curi_eq_cfg, nil, star_count, min_links_count,
        page_link, logger
      )
      if shuffled_result
        if shuffled_result.is_a?(ArchivesSortedResult)
          main_result = shuffled_result
        else
          tentative_better_results << shuffled_result
        end
        min_links_count = shuffled_result.speculative_count + 1
      end
    end
  end

  if main_result.is_a?(ArchivesSortedResult) && main_result.has_dates
    logger.info("Skipping shuffled 2xpaths match because there's already a sorted result with dates")
  else
    extractions_by_masked_xpath_by_star_count.each do |star_count, extractions_by_masked_xpath|
      shuffled_2xpaths_result = try_extract_shuffled_2xpaths(
        extractions_by_masked_xpath_by_star_count[1], extractions_by_masked_xpath, feed_entry_links,
        curi_eq_cfg, star_count, min_links_count, page_link, logger
      )
      if shuffled_2xpaths_result
        if shuffled_2xpaths_result.is_a?(ArchivesSortedResult)
          main_result = shuffled_2xpaths_result
        else
          tentative_better_results << shuffled_2xpaths_result
        end
        min_links_count = shuffled_2xpaths_result.speculative_count + 1
      end
    end
  end

  sorted_almost_fewer_stars_curis = nil
  sorted_almost_fewer_stars_have_dates = nil
  extractions_by_masked_xpath_by_star_count.each do |star_count, extractions_by_masked_xpath|
    sorted_almost_result = try_extract_sorted(
      extractions_by_masked_xpath, feed_entry_links, curi_eq_cfg, almost_match_threshold, star_count,
      sorted_almost_fewer_stars_curis, sorted_almost_fewer_stars_have_dates, min_links_count, page_link,
      logger
    )
    if sorted_almost_result
      main_result = sorted_almost_result
      min_links_count = sorted_almost_result.speculative_count + 1
      sorted_almost_fewer_stars_curis = sorted_almost_result.links.map(&:curi)
      sorted_almost_fewer_stars_have_dates = sorted_almost_result.has_dates
    end
  end

  if main_result.is_a?(ArchivesSortedResult) && main_result.has_dates
    logger.info("Skipping shuffled_almost match because there's already a sorted result with dates")
  else
    extractions_by_masked_xpath_by_star_count.each do |star_count, extractions_by_masked_xpath|
      shuffled_almost_result = try_extract_shuffled(
        page, extractions_by_masked_xpath, feed_entry_links, curi_eq_cfg, almost_match_threshold, star_count,
        min_links_count, page_link, logger
      )
      if shuffled_almost_result
        if shuffled_almost_result.is_a?(ArchivesSortedResult)
          main_result = shuffled_almost_result
        else
          tentative_better_results << shuffled_almost_result
        end
        min_links_count = shuffled_almost_result.speculative_count + 1
      end
    end
  end

  long_feed_result = try_extract_long_feed(
    feed_entry_links, page_curis_set, min_links_count, page_link, logger
  )
  if long_feed_result
    main_result = long_feed_result
    min_links_count = long_feed_result.speculative_count + 1
  end

  results = []
  results << main_result if main_result
  unless tentative_better_results.empty?
    speculative_count = tentative_better_results.map(&:speculative_count).max
    results << ArchivesShuffledResults.new(
      main_link: page_link,
      results: tentative_better_results,
      speculative_count: speculative_count,
      count: nil
    )
  end
  results
end

def try_extract_sorted(
  extractions_by_masked_xpath, feed_entry_links, curi_eq_cfg, almost_match_threshold, star_count,
  fewer_stars_curis, fewer_stars_have_dates, min_links_count, main_link, logger
)
  is_almost = !!almost_match_threshold
  almost_suffix = is_almost ? "_almost" : ""
  markup_dates_extraction_key = is_almost ? :almost_markup_dates_extraction : :markup_dates_extraction
  logger.info("Trying sorted#{almost_suffix} match with #{star_count} stars")

  best_xpath = nil
  best_links = nil
  best_has_dates = nil
  best_pattern = nil
  best_log_str = nil
  extractions_by_masked_xpath.each do |masked_xpath, extraction|
    links_extraction = extraction.links_extraction
    links = links_extraction.links
    curis = links_extraction.curis
    curis_set = links_extraction.curis_set
    dates = extraction[markup_dates_extraction_key].dates
    dates_log_lines = extraction[markup_dates_extraction_key].log_lines

    next if best_links && best_links.length >= links.length
    next if fewer_stars_have_dates && !dates
    next unless links.length >= feed_entry_links.length
    next unless links.length >= min_links_count

    log_lines = extraction.log_lines + dates_log_lines
    if is_almost
      target_feed_entry_links = feed_entry_links.filter_included(curis_set)
      next unless target_feed_entry_links.length < feed_entry_links.length
      next unless target_feed_entry_links.length >= almost_match_threshold
      log_lines << "almost feed match #{target_feed_entry_links.length}/#{feed_entry_links.length}"
    else
      next unless feed_entry_links.all_included?(curis_set)
      target_feed_entry_links = feed_entry_links
    end

    # In 1+*(*(*)) sorted links are deduped to pick the oldest occurrence of each, haven't had a real example
    # in just sorted

    is_matching_feed = target_feed_entry_links.sequence_match(curis, curi_eq_cfg)
    is_matching_fewer_stars_links = fewer_stars_curis &&
      curis[...fewer_stars_curis.length]
        .zip(fewer_stars_curis)
        .all? do |xpath_curi, fewer_stars_curi|
        canonical_uri_equal?(xpath_curi, fewer_stars_curi, curi_eq_cfg)
      end
    if extraction[markup_dates_extraction_key].are_sorted != false &&
      is_matching_feed &&
      !links_extraction.has_duplicates &&
      (!fewer_stars_curis || is_matching_fewer_stars_links)

      best_xpath = masked_xpath
      best_links = links
      best_has_dates = !!dates
      best_pattern = "archives#{almost_suffix}"
      best_log_str = join_log_lines(log_lines)
      logger.info("Masked xpath is good: #{masked_xpath}#{best_log_str}")
      next
    end

    reversed_links = links.reverse
    reversed_curis = curis.reverse
    is_reversed_matching_feed = target_feed_entry_links.sequence_match(reversed_curis, curi_eq_cfg)
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
    if extraction[markup_dates_extraction_key].are_reverse_sorted != false &&
      is_reversed_matching_feed &&
      !links_extraction.has_duplicates &&
      (!fewer_stars_curis ||
        is_reversed_matching_fewer_stars_links_prefix ||
        is_reversed_matching_fewer_stars_links_suffix)

      best_xpath = masked_xpath
      best_links = reversed_links
      best_has_dates = !!dates
      best_pattern = "archives#{almost_suffix}"
      best_log_str = join_log_lines(log_lines)
      logger.info("Masked xpath is good in reverse order: #{masked_xpath}#{best_log_str}")
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
        logger.info("Masked xpath #{masked_xpath} has all links with dates but also duplicates with conflicting dates: #{canonical_urls_dates}")
        next
      end

      sorted_links_dates = sort_links_dates(unique_links_dates)
      sorted_links = sorted_links_dates.map { |link_date| link_date[0] }
      sorted_curis = sorted_links.map(&:curi)
      is_sorted_matching_feed = target_feed_entry_links.sequence_match(sorted_curis, curi_eq_cfg)
      unless is_sorted_matching_feed
        logger.info("Masked xpath #{masked_xpath} has all links with dates but doesn't match feed after sorting")
        sorted_masked_xpath_links_dates_log = sorted_links_dates
          .map { |link_date| [link_date[0].curi.to_s, link_date[1].strftime("%Y-%m-%d")] }
        logger.info("Masked xpath links with dates: #{sorted_masked_xpath_links_dates_log}")
        logger.info("Feed links: #{target_feed_entry_links}")
        next
      end

      # Don't compare with fewer stars canonical urls
      # If it's two stars by category, categories are interspersed and have dates, but one category matches
      # feed, dates are still a good signal to merge the categories

      best_xpath = masked_xpath
      best_links = sorted_links
      best_has_dates = true
      best_pattern = "archives_shuffled#{almost_suffix}"

      if links.length > unique_links_dates.length
        log_lines << "dedup #{links.length} -> #{unique_links_dates.length}"
      end
      newest_date = sorted_links_dates.first[1]
      oldest_date = sorted_links_dates.last[1]
      log_lines << "from #{oldest_date} to #{newest_date}"
      best_log_str = join_log_lines(log_lines)
      logger.info("Masked xpath is good sorted by date: #{masked_xpath}#{best_log_str}")
      next
    end
  end

  if best_links
    if HardcodedBlogs::is_match(main_link, HardcodedBlogs::KALZUMEUS, curi_eq_cfg)
      post_categories = extract_kalzumeus_categories(logger)
      post_categories_str = category_counts_to_s(post_categories)
      logger.info("Categories: #{post_categories_str}")
      post_categories_html = "<br>categories: #{post_categories_str}"
    else
      post_categories = nil
      post_categories_html = ""
    end

    ArchivesSortedResult.new(
      main_link: main_link,
      pattern: best_pattern,
      links: best_links,
      speculative_count: best_links.length,
      count: best_links.length,
      has_dates: best_has_dates,
      post_categories: post_categories,
      extra: "xpath: #{best_xpath}#{best_log_str}#{post_categories_html}"
    )
  else
    logger.info("No sorted match with #{star_count} stars")
    nil
  end
end

def try_extract_sorted_highlight_first_link(
  extractions_by_masked_xpath, feed_entry_links, feed_entry_curis_titles_map, curi_eq_cfg, page_curis_set,
  star_count, fewer_stars_curis, min_links_count, main_link, logger
)
  logger.info("Trying sorted match with highlighted first link and #{star_count} stars")

  best_xpath = nil
  best_first_link = nil
  best_links = nil
  best_log_str = nil
  extractions_by_masked_xpath.each do |masked_xpath, extraction|
    links_extraction = extraction.links_extraction
    links = links_extraction.links
    curis = links_extraction.curis
    curis_set = links_extraction.curis_set

    log_lines = extraction.log_lines.clone
    if feed_entry_links.length == feed_entry_curis_titles_map.length
      dedup_other_links = []
      dedup_other_curis_set = CanonicalUriSet.new([], curi_eq_cfg)
      links.reverse_each do |link|
        next if dedup_other_curis_set.include?(link.curi)

        dedup_other_links << link
        dedup_other_curis_set << link.curi
      end
      dedup_other_links.reverse!
      dedup_last_curis = dedup_other_links.map(&:curi)

      if dedup_other_links.length != links.length
        log_lines << "dedup #{links.length} -> #{dedup_other_links.length}"
      end
    else
      dedup_other_links = links
      dedup_last_curis = curis
    end

    next if best_links && best_links.length >= dedup_other_links.length
    next unless dedup_other_links.length >= feed_entry_links.length - 1
    next unless dedup_other_links.length >= min_links_count - 1

    is_matching_feed, first_link = feed_entry_links.sequence_match_except_first?(
      dedup_last_curis, curi_eq_cfg
    )
    is_matching_fewer_stars_links = fewer_stars_curis &&
      fewer_stars_curis[1..]
        .zip(dedup_last_curis[...fewer_stars_curis.length - 1])
        .all? do |xpath_uri, fewer_stars_uri|
        canonical_uri_equal?(xpath_uri, fewer_stars_uri, curi_eq_cfg)
      end
    if is_matching_feed &&
      page_curis_set.include?(first_link.curi) &&
      !curis_set.include?(first_link.curi) &&
      (is_matching_fewer_stars_links || !fewer_stars_curis)

      best_xpath = masked_xpath
      best_first_link = first_link
      best_links = dedup_other_links
      best_log_str = join_log_lines(log_lines)
      logger.info("Masked xpath is good: #{masked_xpath}#{best_log_str}")
      next
    end
  end

  if best_links && best_first_link
    ArchivesSortedResult.new(
      main_link: main_link,
      pattern: "archives_2xpaths",
      links: [best_first_link] + best_links,
      speculative_count: 1 + best_links.length,
      count: 1 + best_links.length,
      has_dates: nil,
      extra: "counts: 1 + #{best_links.length}<br>suffix_xpath: #{best_xpath}#{best_log_str}",
    )
  else
    logger.info("No sorted match with highlighted first link and #{star_count} stars")
    nil
  end
end

def try_extract_medium_pinned_entry(
  extractions_by_masked_xpath, feed_entry_links, curi_eq_cfg, feed_generator, page_links, min_links_count,
  main_link, logger
)
  logger.info("Trying medium match with pinned entry")

  unless feed_generator == :medium
    logger.info("Feed generator is not Medium")
    return nil
  end

  extractions_by_masked_xpath.each do |masked_xpath, extraction|
    links_extraction = extraction.links_extraction
    links = links_extraction.links
    canonical_uris_set = links_extraction.curis_set
    medium_markup_dates_extraction = extraction.medium_markup_dates_extraction

    next unless links.length >= feed_entry_links.length - 1
    next unless links.length >= min_links_count - 1
    next unless medium_markup_dates_extraction.dates

    feed_links_not_matching = feed_entry_links
      .to_a
      .filter { |entry_link| !canonical_uris_set.include?(entry_link.curi) }
    next unless feed_links_not_matching.length == 1

    pinned_entry_link = page_links.find do |page_link|
      canonical_uri_equal?(page_link.curi, feed_links_not_matching.first.curi, curi_eq_cfg)
    end
    next unless pinned_entry_link

    other_links_dates = links.zip(medium_markup_dates_extraction.dates)

    log_lines = extraction.log_lines + medium_markup_dates_extraction.log_lines
    log_lines << "1 + #{other_links_dates.length} links"
    log_str = join_log_lines(log_lines)
    logger.info("Masked xpath is good with medium pinned entry: #{masked_xpath}#{log_str}")
    return ArchivesMediumPinnedEntryResult.new(
      main_link: main_link,
      pattern: "archives_shuffled_2xpaths",
      pinned_entry_link: pinned_entry_link,
      other_links_dates: other_links_dates,
      speculative_count: 1 + other_links_dates.length,
      count: nil,
      extra: "counts: 1 + #{links.length}<br>pinned_link_xpath: #{pinned_entry_link.xpath}<br>suffix_xpath: #{masked_xpath}#{log_str}",
    )
  end

  logger.info("No medium match with pinned entry")
  nil
end

def try_extract_sorted_2xpaths(
  prefix_extractions_by_masked_xpath, suffix_extractions_by_masked_xpath, feed_entry_links, curi_eq_cfg,
  star_count, fewer_stars_curis, min_links_count, main_link, logger
)
  logger.info("Trying sorted match with 1+#{star_count} stars")

  feed_prefix_xpaths_by_length = {}
  prefix_extractions_by_masked_xpath.each do |masked_prefix_xpath, prefix_extraction|
    links = prefix_extraction.links_extraction.links
    curis = prefix_extraction.links_extraction.curis
    next if links.length >= feed_entry_links.length
    next unless feed_entry_links.sequence_match(curis, curi_eq_cfg)

    unless feed_prefix_xpaths_by_length.key?(links.length)
      feed_prefix_xpaths_by_length[links.length] = []
    end
    feed_prefix_xpaths_by_length[links.length] << masked_prefix_xpath
  end

  best_links = nil
  best_prefix_xpath = nil
  best_suffix_xpath = nil
  best_prefix_count = nil
  best_suffix_count = nil
  best_prefix_log_str = nil
  best_suffix_log_str = nil

  suffix_extractions_by_masked_xpath.each do |masked_suffix_xpath, suffix_extraction|
    suffix_links_extraction = suffix_extraction.links_extraction
    suffix_links = suffix_links_extraction.links
    suffix_curis = suffix_links_extraction.curis

    # In 1+*(*(*)) sorted links are deduped to pick the oldest occurrence of each, haven't had a real example
    # here

    suffix_matching_links, target_prefix_length = feed_entry_links.sequence_is_suffix?(
      suffix_curis, curi_eq_cfg
    )
    next unless suffix_matching_links
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

    logger.info("Found partition with two xpaths: #{target_prefix_length} + #{suffix_links.length}")
    prefix_log_str = join_log_lines(prefix_extraction.log_lines)
    suffix_log_str = join_log_lines(suffix_extraction.log_lines)
    logger.info("Prefix xpath: #{masked_prefix_xpath}#{prefix_log_str}")
    logger.info("Suffix xpath: #{masked_suffix_xpath}#{suffix_log_str}")

    combined_links = prefix_links + suffix_links
    combined_curis = combined_links.map(&:curi)
    combined_curis_set = combined_curis.to_canonical_uri_set(curi_eq_cfg)
    if combined_curis.length != combined_curis_set.length
      logger.info("Combination has all feed links but also duplicates: #{combined_curis.map(&:to_s)}")
      next
    end

    is_matching_prev_archives_links = !fewer_stars_curis ||
      fewer_stars_curis
        .zip(combined_curis[...fewer_stars_curis.length])
        .all? do |xpath_curi, fewer_stars_curi|
        canonical_uri_equal?(xpath_curi, fewer_stars_curi, curi_eq_cfg)
      end
    unless is_matching_prev_archives_links
      logger.info("Combination doesn't match previous archives links")
      next
    end

    best_links = combined_links
    best_prefix_xpath = masked_prefix_xpath
    best_suffix_xpath = masked_suffix_xpath
    best_prefix_count = target_prefix_length
    best_suffix_count = suffix_links.length
    best_prefix_log_str = prefix_log_str
    best_suffix_log_str = suffix_log_str
    logger.info("Combination is good (#{combined_links.length} links)")
  end

  if best_links
    ArchivesSortedResult.new(
      main_link: main_link,
      pattern: "archives_2xpaths",
      links: best_links,
      speculative_count: best_links.length,
      count: best_links.length,
      has_dates: nil,
      extra: "star_count: 1 + #{star_count}<br>counts: #{best_prefix_count} + #{best_suffix_count}<br>prefix_xpath: #{best_prefix_xpath}#{best_prefix_log_str}<br>suffix_xpath: #{best_suffix_xpath}#{best_suffix_log_str}"
    )
  else
    logger.info("No sorted match with 1+#{star_count} stars")
    nil
  end
end

def try_extract_almost_matching_feed(
  extractions_by_masked_xpath, feed_entry_links, feed_entry_curis_titles_map, curi_eq_cfg,
  almost_match_threshold, star_count, fewer_stars_curis, main_link, logger
)
  logger.info("Trying almost feed match with #{star_count} stars")

  best_links = nil
  best_xpath = nil
  best_log_str = nil

  extractions_by_masked_xpath.each do |masked_xpath, extraction|
    links_extraction = extraction.links_extraction
    links = links_extraction.links
    curis = links_extraction.curis
    curis_set = links_extraction.curis_set

    next if best_links && best_links.length >= links.length
    next unless links.length < feed_entry_links.length
    next unless links.length >= almost_match_threshold
    next unless feed_entry_links.count_included(curis_set) >= almost_match_threshold
    next unless curis.all? { |curi| feed_entry_curis_titles_map.include?(curi) }

    is_matching_fewer_stars_links = fewer_stars_curis &&
      curis[...fewer_stars_curis.length]
        .zip(fewer_stars_curis)
        .all? do |xpath_curi, fewer_stars_curi|
        canonical_uri_equal?(xpath_curi, fewer_stars_curi, curi_eq_cfg)
      end
    next unless !fewer_stars_curis || is_matching_fewer_stars_links

    best_links = links
    best_xpath = masked_xpath
    log_lines = extraction.log_lines.clone
    log_lines << "#{links.length}/#{feed_entry_links.length} feed links"
    best_log_str = join_log_lines(log_lines)
    logger.info("Masked xpath almost matches feed: #{masked_xpath}#{best_log_str}")
  end

  if best_links
    ArchivesSortedResult.new(
      main_link: main_link,
      pattern: "archives_feed_almost",
      links: feed_entry_links.to_a,
      speculative_count: feed_entry_links.length,
      count: feed_entry_links.length,
      extra: "xpath:#{best_xpath}#{best_log_str}"
    )
  else
    logger.info("No almost feed match with #{star_count} stars")
    nil
  end
end

ArchivesShuffledResult = Struct.new(
  :main_link, :pattern, :links_maybe_dates, :speculative_count, :post_categories, :extra, keyword_init: true
)

def try_extract_shuffled(
  page, extractions_by_masked_xpath, feed_entry_links, curi_eq_cfg, almost_match_threshold, star_count,
  min_links_count, main_link, logger
)
  is_almost = !!almost_match_threshold
  almost_suffix = is_almost ? "_almost" : ""
  logger.info("Trying shuffled#{almost_suffix} match with #{star_count} stars")

  best_links_maybe_dates = nil
  best_xpath = nil
  best_log_str = nil

  extractions_by_masked_xpath.each do |masked_xpath, extraction|
    links_extraction = extraction.links_extraction
    links = links_extraction.links
    curis = links_extraction.curis
    curis_set = links_extraction.curis_set

    next if best_links_maybe_dates && best_links_maybe_dates.length >= links.length
    next unless links.length >= feed_entry_links.length
    next unless links.length >= min_links_count

    log_lines = extraction.log_lines +
      extraction.maybe_url_dates_extraction.log_lines +
      extraction.some_markup_dates_extraction.log_lines
    if is_almost
      target_feed_entry_links = feed_entry_links.filter_included(curis_set)
      next unless target_feed_entry_links.length < feed_entry_links.length
      next unless target_feed_entry_links.length >= almost_match_threshold
      log_lines << "almost feed match #{target_feed_entry_links.length}/#{feed_entry_links.length}"
    else
      next unless feed_entry_links.all_included?(curis_set)
    end

    maybe_dates = extraction
      .maybe_url_dates_extraction.dates
      .zip(extraction.some_markup_dates_extraction.dates || [])
      .map { |maybe_url_date, maybe_markup_date| maybe_url_date || maybe_markup_date }

    links_maybe_dates = links.zip(maybe_dates)
    if curis.length != curis_set.length
      dedup_links_maybe_dates = []
      dedup_curis_set = CanonicalUriSet.new([], curi_eq_cfg)
      links_maybe_dates.each do |link, maybe_date|
        next if dedup_curis_set.include?(link.curi)

        dedup_links_maybe_dates << [link, maybe_date]
        dedup_curis_set << link.curi
      end
    else
      dedup_links_maybe_dates = links_maybe_dates
    end

    best_links_maybe_dates = dedup_links_maybe_dates
    best_xpath = masked_xpath
    if links.length > dedup_links_maybe_dates.length
      log_lines << "dedup #{links.length} -> #{dedup_links_maybe_dates.length}"
    end
    best_log_str = join_log_lines(log_lines)
    logger.info("Masked xpath is good but shuffled: #{masked_xpath}#{best_log_str}")
  end

  if best_links_maybe_dates
    dates_present = best_links_maybe_dates.count { |_, date| date }

    if HardcodedBlogs::is_match(main_link, HardcodedBlogs::JULIA_EVANS, curi_eq_cfg)
      post_categories = extract_jvns_categories(page, logger)
      post_categories_str = category_counts_to_s(post_categories)
      logger.info("Categories: #{post_categories_str}")
      post_categories_html = "<br>categories: #{post_categories_str}"
    else
      post_categories = nil
      post_categories_html = ""
    end

    ArchivesShuffledResult.new(
      main_link: main_link,
      pattern: "archives_shuffled#{almost_suffix}",
      links_maybe_dates: best_links_maybe_dates,
      speculative_count: best_links_maybe_dates.count,
      post_categories: post_categories,
      extra: "xpath: #{best_xpath}#{best_log_str}<br>dates_present: #{dates_present}/#{best_links_maybe_dates.length}#{post_categories_html}"
    )
  else
    logger.info("No shuffled match with #{star_count} stars")
    nil
  end
end

def try_extract_shuffled_2xpaths(
  prefix_extractions_by_masked_xpath, suffix_extractions_by_masked_xpath, feed_entry_links, curi_eq_cfg,
  star_count, min_links_count, main_link, logger
)
  logger.info("Trying shuffled match with 1+#{star_count} stars")

  best_prefix_links_maybe_dates = nil
  best_prefix_xpath = nil
  best_prefix_curis = nil
  best_prefix_log_str = nil
  prefix_extractions_by_masked_xpath.each do |masked_prefix_xpath, prefix_extraction|
    prefix_links = prefix_extraction.links_extraction.links
    prefix_curis = prefix_extraction.links_extraction.curis
    next if prefix_links.length >= feed_entry_links.length
    next if best_prefix_links_maybe_dates && prefix_links.length <= best_prefix_links_maybe_dates.length
    next unless feed_entry_links.sequence_match(prefix_curis, curi_eq_cfg)

    prefix_maybe_dates = prefix_extraction
      .maybe_url_dates_extraction.dates
      .zip(prefix_extraction.some_markup_dates_extraction.dates || [])
      .map { |maybe_url_date, maybe_markup_date| maybe_url_date || maybe_markup_date }
    prefix_log_lines = prefix_extraction.log_lines +
      prefix_extraction.maybe_url_dates_extraction.log_lines +
      prefix_extraction.some_markup_dates_extraction.log_lines

    best_prefix_links_maybe_dates = prefix_links.zip(prefix_maybe_dates)
    best_prefix_xpath = masked_prefix_xpath
    best_prefix_curis = prefix_curis
    best_prefix_log_str = join_log_lines(prefix_log_lines)
  end

  unless best_prefix_links_maybe_dates
    logger.info("No shuffled match with 1+#{star_count} stars")
    return nil
  end

  best_links_maybe_dates = nil
  best_suffix_links_maybe_dates = nil
  best_suffix_xpath = nil
  best_suffix_log_str = nil
  suffix_extractions_by_masked_xpath.each do |masked_suffix_xpath, suffix_extraction|
    suffix_links_extraction = suffix_extraction.links_extraction
    suffix_links = suffix_links_extraction.links
    suffix_curis = suffix_links_extraction.curis

    next if best_suffix_links_maybe_dates && best_suffix_links_maybe_dates.length >= suffix_links.length
    next unless suffix_links.length >= feed_entry_links.length
    next unless suffix_links.length >= min_links_count

    curis = best_prefix_curis + suffix_curis
    curis_set = CanonicalUriSet.new(curis, curi_eq_cfg)
    next unless feed_entry_links.all_included?(curis_set)

    suffix_log_lines = suffix_extraction.log_lines +
      suffix_extraction.maybe_url_dates_extraction.log_lines +
      suffix_extraction.some_markup_dates_extraction.log_lines
    suffix_maybe_dates = suffix_extraction
      .maybe_url_dates_extraction.dates
      .zip(suffix_extraction.some_markup_dates_extraction.dates || [])
      .map { |maybe_url_date, maybe_markup_date| maybe_url_date || maybe_markup_date }

    suffix_links_maybe_dates = suffix_links.zip(suffix_maybe_dates)
    links_maybe_dates = best_prefix_links_maybe_dates + suffix_links_maybe_dates
    if curis.length != curis_set.length
      dedup_links_maybe_dates = []
      dedup_curis_set = CanonicalUriSet.new([], curi_eq_cfg)
      links_maybe_dates.each do |link, maybe_date|
        next if dedup_curis_set.include?(link.curi)

        dedup_links_maybe_dates << [link, maybe_date]
        dedup_curis_set << link.curi
      end
    else
      dedup_links_maybe_dates = links_maybe_dates
    end

    best_links_maybe_dates = dedup_links_maybe_dates
    best_suffix_links_maybe_dates = suffix_links_maybe_dates
    best_suffix_xpath = masked_suffix_xpath
    if links_maybe_dates.length > dedup_links_maybe_dates.length
      suffix_log_lines << "dedup #{links_maybe_dates.length} -> #{dedup_links_maybe_dates.length}"
    end
    best_suffix_log_str = join_log_lines(suffix_log_lines)

    logger.info("Found partition with two xpaths: #{best_prefix_links_maybe_dates.length} + #{suffix_links.length}}")
    logger.info("Prefix xpath: #{best_prefix_xpath}#{best_prefix_log_str}")
    logger.info("Suffix xpath: #{masked_suffix_xpath}#{best_suffix_log_str}")
  end

  if best_links_maybe_dates
    dates_present = best_links_maybe_dates.count { |_, date| date }
    if dates_present == best_links_maybe_dates.length
      sorted_links_dates = sort_links_dates(best_links_maybe_dates)
      sorted_links = sorted_links_dates.map(&:first)
      ArchivesSortedResult.new(
        main_link: main_link,
        pattern: "archives_shuffled_2xpaths",
        links: sorted_links,
        speculative_count: sorted_links.count,
        count: sorted_links.count,
        has_dates: nil,
        extra: "star_count: 1 + #{star_count}<br>counts: #{best_prefix_links_maybe_dates.length} + #{best_suffix_links_maybe_dates.length}<br>prefix_xpath: #{best_prefix_xpath}#{best_prefix_log_str}<br>suffix_xpath: #{best_suffix_xpath}#{best_suffix_log_str}<br>dates_present: #{dates_present}/#{sorted_links.length}"
      )
    else
      ArchivesShuffledResult.new(
        pattern: "archives_shuffled_2xpaths",
        links_maybe_dates: best_links_maybe_dates,
        speculative_count: best_links_maybe_dates.count,
        extra: "star_count: 1 + #{star_count}<br>counts: #{best_prefix_links_maybe_dates.length} + #{best_suffix_links_maybe_dates.length}<br>prefix_xpath: #{best_prefix_xpath}#{best_prefix_log_str}<br>suffix_xpath: #{best_suffix_xpath}#{best_suffix_log_str}<br>dates_present: #{dates_present}/#{best_links_maybe_dates.length}"
      )
    end
  else
    logger.info("No shuffled match with 1+#{star_count} stars")
    nil
  end
end

def try_extract_long_feed(feed_entry_links, page_curis_set, min_links_count, main_link, logger)
  logger.info("Trying archives long feed match")

  if feed_entry_links.length >= 31 &&
    feed_entry_links.length > min_links_count &&
    feed_entry_links.all_included?(page_curis_set)

    logger.info("Long feed is matching (#{feed_entry_links.length} links)")
    LongFeedResult.new(
      main_link: main_link,
      pattern: "archives_long_feed",
      links: feed_entry_links.to_a,
      speculative_count: feed_entry_links.length,
      count: feed_entry_links.length,
      extra: ""
    )
  else
    logger.info("No archives long feed match")
    nil
  end
end