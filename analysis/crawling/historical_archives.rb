require 'set'
require_relative 'date_extraction'
require_relative 'historical_archives_sort'
require_relative 'historical_common'

ArchivesResult = Struct.new(:main_result, :tentative_better_results)

def try_extract_archives(
  page, page_links, page_canonical_uris_set, feed_entry_links, feed_entry_canonical_uris,
  feed_entry_canonical_uris_set, feed_generator, canonical_equality_cfg, min_links_count, logger
)
  almost_match_threshold = get_almost_match_threshold(feed_entry_canonical_uris.length)
  return nil unless feed_entry_canonical_uris
    .count { |item_uri| page_canonical_uris_set.include?(item_uri) } >= almost_match_threshold
  logger.log("Possible archives page: #{page.canonical_uri}")

  star_count_xpath_names = [
    [1, :xpath],
    [2, :class_xpath],
    [3, :class_xpath]
  ]

  extractions_by_masked_xpath_by_star_count = {}
  star_count_xpath_names.each do |star_count, xpath_name|
    links_by_masked_xpath = group_links_by_masked_xpath(
      page_links, feed_entry_canonical_uris_set, xpath_name, star_count
    )
    logger.log("Masked xpaths with #{star_count} stars: #{links_by_masked_xpath.length}")

    extractions_by_masked_xpath = links_by_masked_xpath.to_h do |masked_xpath, masked_xpath_links|
      [
        masked_xpath,
        get_masked_xpath_extraction(
          masked_xpath, masked_xpath_links, star_count, feed_entry_canonical_uris,
          feed_entry_canonical_uris_set, canonical_equality_cfg, almost_match_threshold, logger
        )
      ]
    end

    extractions_by_masked_xpath_by_star_count[star_count] = extractions_by_masked_xpath
  end

  main_result = nil

  sorted_fewer_stars_canonical_uris = nil
  sorted_fewer_stars_have_dates = nil
  extractions_by_masked_xpath_by_star_count.each do |star_count, extractions_by_masked_xpath|
    sorted_result = try_extract_sorted(
      extractions_by_masked_xpath, feed_entry_canonical_uris, canonical_equality_cfg, nil,
      star_count, sorted_fewer_stars_canonical_uris, sorted_fewer_stars_have_dates, min_links_count, logger
    )
    if sorted_result
      main_result = sorted_result
      min_links_count = sorted_result.count + 1
      sorted_fewer_stars_canonical_uris = sorted_result.links.map(&:canonical_uri)
      sorted_fewer_stars_have_dates = sorted_result.has_dates
    end
  end

  if feed_entry_canonical_uris.length >= 3
    sorted1_fewer_stars_canonical_uris = nil
    extractions_by_masked_xpath_by_star_count.each do |star_count, extractions_by_masked_xpath|
      sorted1_result = try_extract_sorted_highlight_first_link(
        extractions_by_masked_xpath, feed_entry_canonical_uris, canonical_equality_cfg, page_links,
        star_count, sorted1_fewer_stars_canonical_uris, min_links_count, logger
      )
      if sorted1_result
        main_result = sorted1_result
        min_links_count = sorted1_result.count + 1
        sorted1_fewer_stars_canonical_uris = sorted1_result.links.map(&:canonical_uri)
      end
    end
  end

  medium_pinned_entry_result = try_extract_medium_with_pinned_entry(
    extractions_by_masked_xpath_by_star_count[1], feed_entry_canonical_uris, canonical_equality_cfg,
    feed_generator, page_links, min_links_count, logger
  )
  if medium_pinned_entry_result
    main_result = medium_pinned_entry_result
    min_links_count = medium_pinned_entry_result.count + 1
  end

  sorted_2xpaths_fewer_stars_canonical_uris = nil
  extractions_by_masked_xpath_by_star_count.each do |star_count, extractions_by_masked_xpath|
    sorted_2xpaths_result = try_extract_sorted_2xpaths(
      extractions_by_masked_xpath_by_star_count[1], extractions_by_masked_xpath, feed_entry_canonical_uris,
      canonical_equality_cfg, star_count, sorted_2xpaths_fewer_stars_canonical_uris, min_links_count, logger
    )
    if sorted_2xpaths_result
      main_result = sorted_2xpaths_result
      min_links_count = sorted_2xpaths_result.count + 1
      sorted_2xpaths_fewer_stars_canonical_uris = sorted_2xpaths_result.links.map(&:canonical_uri)
    end
  end

  almost_feed_fewer_stars_canonical_uris = nil
  extractions_by_masked_xpath_by_star_count.each do |star_count, extractions_by_masked_xpath|
    almost_feed_result = try_extract_almost_matching_feed(
      extractions_by_masked_xpath, feed_entry_links, feed_entry_canonical_uris_set, canonical_equality_cfg,
      almost_match_threshold, star_count, almost_feed_fewer_stars_canonical_uris, min_links_count,
      logger
    )
    if almost_feed_result
      main_result = almost_feed_result
      min_links_count = almost_feed_result.count + 1
      almost_feed_fewer_stars_canonical_uris = almost_feed_result.links.map(&:canonical_uri)
    end
  end

  tentative_better_results = []

  unless main_result.is_a?(SortedResult) && main_result.has_dates
    extractions_by_masked_xpath_by_star_count.each do |star_count, extractions_by_masked_xpath|
      shuffled_result = try_extract_shuffled(
        extractions_by_masked_xpath, feed_entry_canonical_uris, canonical_equality_cfg,
        nil, star_count, min_links_count, logger
      )
      if shuffled_result
        tentative_better_results << shuffled_result
        min_links_count = shuffled_result.count + 1
      end
    end
  end

  sorted_almost_fewer_stars_canonical_uris = nil
  sorted_almost_fewer_stars_have_dates = nil
  extractions_by_masked_xpath_by_star_count.each do |star_count, extractions_by_masked_xpath|
    sorted_almost_result = try_extract_sorted(
      extractions_by_masked_xpath, feed_entry_canonical_uris, canonical_equality_cfg, almost_match_threshold,
      star_count, sorted_almost_fewer_stars_canonical_uris, sorted_almost_fewer_stars_have_dates,
      min_links_count, logger
    )
    if sorted_almost_result
      main_result = sorted_almost_result
      min_links_count = sorted_almost_result.count + 1
      sorted_almost_fewer_stars_canonical_uris = sorted_almost_result.links.map(&:canonical_uri)
      sorted_almost_fewer_stars_have_dates = sorted_almost_result.has_dates
    end
  end

  extractions_by_masked_xpath_by_star_count.each do |star_count, extractions_by_masked_xpath|
    shuffled_almost_result = try_extract_shuffled(
      extractions_by_masked_xpath, feed_entry_canonical_uris, canonical_equality_cfg, almost_match_threshold,
      star_count, min_links_count, logger
    )
    if shuffled_almost_result
      tentative_better_results << shuffled_almost_result
      min_links_count = shuffled_almost_result.count + 1
    end
  end

  ArchivesResult.new(main_result, tentative_better_results)
end

def get_almost_match_threshold(feed_length)
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

LinksExtraction = Struct.new(:links, :canonical_uris, :canonical_uris_set, :has_duplicates)
DatesExtraction = Struct.new(:dates, :are_sorted, :are_reverse_sorted)
MaskedXpathExtraction = Struct.new(
  :links_extraction, :log_lines, :markup_dates_extraction, :medium_markup_dates,
  :almost_markup_dates_extraction, :maybe_url_dates
)

def get_masked_xpath_extraction(
  masked_xpath, links, star_count, feed_entry_canonical_uris, feed_entry_canonical_uris_set,
  canonical_equality_cfg, almost_match_threshold, logger
)
  collapsed_links = []
  links.length.times do |index|
    if index == 0 ||
      !canonical_uri_equal?(
        links[index].canonical_uri, links[index - 1].canonical_uri, canonical_equality_cfg
      )

      collapsed_links << links[index]
    end
  end

  log_lines = []
  if links.length != collapsed_links.length
    log_lines << "collapsed #{links.length} -> #{collapsed_links.length}"
  end

  filtered_links = collapsed_links
  markup_dates_extraction = DatesExtraction.new(nil, nil, nil)
  medium_markup_dates = nil
  almost_markup_dates_extraction = DatesExtraction.new(nil, nil, nil)

  links_matching_feed = collapsed_links
    .filter { |link| feed_entry_canonical_uris_set.include?(link.canonical_uri) }
  unique_links_matching_feed_count = links_matching_feed
    .map(&:canonical_uri)
    .to_canonical_uri_set(canonical_equality_cfg)
    .length
  threshold_to_have_some_dates = [almost_match_threshold, feed_entry_canonical_uris.length - 1].min

  if unique_links_matching_feed_count >= threshold_to_have_some_dates
    last_star_index = masked_xpath.rindex("*")
    distance_to_top_parent = masked_xpath[last_star_index..].count("/")
    relative_xpath_to_top_parent = "/.." * distance_to_top_parent

    if unique_links_matching_feed_count >= almost_match_threshold
      matching_maybe_markup_dates = extract_maybe_markup_dates(
        collapsed_links, links_matching_feed, distance_to_top_parent, relative_xpath_to_top_parent,
        false, logger
      )

      if matching_maybe_markup_dates
        filtered_links, matching_markup_dates = collapsed_links
          .zip(matching_maybe_markup_dates)
          .filter { |_, date| date != nil }
          .transpose
        if filtered_links.length != links.length
          log_lines << "filtered by dates #{collapsed_links.length} -> #{filtered_links.length}"
        end

        if star_count >= 2
          matching_are_sorted = matching_markup_dates
            .each_cons(2)
            .all? { |date1, date2| date1 >= date2 }
          matching_are_reverse_sorted = matching_markup_dates
            .each_cons(2)
            .all? { |date1, date2| date1 <= date2 }
        else
          # Trust the ordering of links more than dates
          matching_are_sorted = nil
          matching_are_reverse_sorted = nil
        end

        if unique_links_matching_feed_count == feed_entry_canonical_uris.length
          markup_dates_extraction = DatesExtraction.new(
            matching_markup_dates, matching_are_sorted, matching_are_reverse_sorted
          )
        else
          almost_markup_dates_extraction = DatesExtraction.new(
            matching_markup_dates, matching_are_sorted, matching_are_reverse_sorted
          )
        end
      end
    end

    if unique_links_matching_feed_count == feed_entry_canonical_uris.length - 1
      maybe_medium_markup_dates = extract_maybe_markup_dates(
        collapsed_links, links_matching_feed, distance_to_top_parent, relative_xpath_to_top_parent,
        true, logger
      )

      if maybe_medium_markup_dates && maybe_medium_markup_dates.all? { |date| date != nil }
        medium_markup_dates = maybe_medium_markup_dates
      end
    end
  end

  canonical_uris = filtered_links.map(&:canonical_uri)
  canonical_uris_set = canonical_uris.to_canonical_uri_set(canonical_equality_cfg)
  has_duplicates = canonical_uris.length != canonical_uris_set.length
  links_extraction = LinksExtraction.new(filtered_links, canonical_uris, canonical_uris_set, has_duplicates)

  maybe_url_dates = filtered_links.map do |link|
    next unless link.canonical_uri.path

    date_match = link.canonical_uri.path.match(/\/(\d{4})\/(\d{2})\/(\d{2})/)
    next unless date_match

    begin
      year = date_match[1].to_i
      month = date_match[2].to_i
      day = date_match[3].to_i
      Date.new(year, month, day)
    rescue
      next
    end
  end

  MaskedXpathExtraction.new(
    links_extraction, log_lines, markup_dates_extraction, medium_markup_dates, almost_markup_dates_extraction,
    maybe_url_dates
  )
end

def extract_maybe_markup_dates(
  links, links_matching_feed, distance_to_top_parent, relative_xpath_to_top_parent, guess_year, logger
)
  date_relative_xpaths_sources = []
  links_matching_feed.each_with_index do |link, index|
    link_top_parent = link.element
    distance_to_top_parent.times do
      link_top_parent = link_top_parent.parent
    end
    link_top_parent_path = link_top_parent.path
    link_date_relative_xpaths_sources = []
    link_top_parent.traverse do |element|
      date_source = try_extract_element_date(element, guess_year)
      next unless date_source

      date_relative_xpath = (relative_xpath_to_top_parent + element.path[link_top_parent_path.length..])
        .delete_prefix("/")
      relative_xpath_source = { xpath: date_relative_xpath, source: date_source[:source] }
      link_date_relative_xpaths_sources << relative_xpath_source if date_source[:date]
    end

    if index == 0
      date_relative_xpaths_sources = link_date_relative_xpaths_sources
    else
      link_full_date_relative_xpaths_sources_set = link_date_relative_xpaths_sources.to_set
      date_relative_xpaths_sources
        .filter! { |xpath_source| link_full_date_relative_xpaths_sources_set.include?(xpath_source) }
    end
  end

  date_relative_xpaths_from_time = date_relative_xpaths_sources
    .filter_map { |xpath_source| xpath_source[:source] == :time ? xpath_source[:xpath] : nil }
  if date_relative_xpaths_sources.length == 1
    date_relative_xpath = date_relative_xpaths_sources.first[:xpath]
  elsif date_relative_xpaths_from_time.length == 1
    date_relative_xpath = date_relative_xpaths_from_time.first
  else
    return nil
  end

  maybe_dates = links.map do |link|
    link_dates = link
      .element
      .xpath(date_relative_xpath)
      .to_a
      .filter_map { |element| try_extract_element_date(element, guess_year) }
      .map { |date_source| date_source[:date] }
    next if link_dates.empty?

    if link_dates.length > 1
      logger.log("Multiple dates found for #{link.xpath} + #{date_relative_xpath}: #{link_dates}")
      next
    end

    link_dates.first
  end

  maybe_dates
end

SortedResult = Struct.new(:pattern, :links, :count, :has_dates, :extra, keyword_init: true)

def try_extract_sorted(
  extractions_by_masked_xpath, feed_entry_canonical_uris, canonical_equality_cfg, almost_match_threshold,
  star_count, fewer_stars_canonical_uris, fewer_stars_have_dates, min_links_count, logger
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
    canonical_uris = links_extraction.canonical_uris
    canonical_uris_set = links_extraction.canonical_uris_set
    dates = extraction.markup_dates_extraction.dates

    next if best_links && best_links.length >= links.length
    next if fewer_stars_have_dates && !dates
    next unless links.length >= feed_entry_canonical_uris.length
    next unless links.length >= min_links_count

    log_lines = extraction.log_lines.clone
    if is_almost
      target_feed_entry_canonical_uris = feed_entry_canonical_uris
        .filter { |entry_uri| canonical_uris_set.include?(entry_uri) }
      next unless target_feed_entry_canonical_uris.length < feed_entry_canonical_uris.length
      next unless target_feed_entry_canonical_uris.length >= almost_match_threshold
      log_lines << "almost feed match #{target_feed_entry_canonical_uris.length}/#{feed_entry_canonical_uris.length}"
    else
      next unless feed_entry_canonical_uris.all? { |entry_uri| canonical_uris_set.include?(entry_uri) }
      target_feed_entry_canonical_uris = feed_entry_canonical_uris
    end

    is_matching_feed = target_feed_entry_canonical_uris
      .zip(canonical_uris[...target_feed_entry_canonical_uris.length])
      .all? { |uri, entry_uri| canonical_uri_equal?(uri, entry_uri, canonical_equality_cfg) }
    is_matching_fewer_stars_links = fewer_stars_canonical_uris &&
      canonical_uris[...fewer_stars_canonical_uris.length]
        .zip(fewer_stars_canonical_uris)
        .all? { |uri, fewer_stars_uri| canonical_uri_equal?(uri, fewer_stars_uri, canonical_equality_cfg) }
    if extraction.markup_dates_extraction.are_sorted != false &&
      is_matching_feed &&
      !links_extraction.has_duplicates &&
      (!fewer_stars_canonical_uris || is_matching_fewer_stars_links)

      best_xpath = masked_xpath
      best_links = links
      best_has_dates = !!dates
      best_pattern = "archives#{almost_suffix}"
      log_lines << "has dates" if best_has_dates
      logger.log("Masked xpath is good: #{masked_xpath}#{join_log_lines(log_lines)} (#{links.length} links)")
      next
    end

    reversed_links = links.reverse
    reversed_canonical_uris = canonical_uris.reverse
    is_reversed_matching_feed = target_feed_entry_canonical_uris
      .zip(reversed_canonical_uris[...target_feed_entry_canonical_uris.length])
      .all? { |uri, entry_uri| canonical_uri_equal?(uri, entry_uri, canonical_equality_cfg) }
    is_reversed_matching_fewer_stars_links_prefix = fewer_stars_canonical_uris &&
      reversed_canonical_uris[...fewer_stars_canonical_uris.length]
        .zip(fewer_stars_canonical_uris)
        .all? do |uri, fewer_stars_uri|
        canonical_uri_equal?(uri, fewer_stars_uri, canonical_equality_cfg)
      end
    is_reversed_matching_fewer_stars_links_suffix = fewer_stars_canonical_uris &&
      reversed_canonical_uris[-fewer_stars_canonical_uris.length..]
        .zip(fewer_stars_canonical_uris)
        .all? do |uri, fewer_stars_uri|
        canonical_uri_equal?(uri, fewer_stars_uri, canonical_equality_cfg)
      end
    if extraction.markup_dates_extraction.are_reverse_sorted != false &&
      is_reversed_matching_feed &&
      !links_extraction.has_duplicates &&
      (!fewer_stars_canonical_uris ||
        is_reversed_matching_fewer_stars_links_prefix ||
        is_reversed_matching_fewer_stars_links_suffix)

      best_xpath = masked_xpath
      best_links = reversed_links
      best_has_dates = !!dates
      best_pattern = "archives#{almost_suffix}"
      log_lines << "has dates" if best_has_dates
      logger.log("Masked xpath is good in reverse order: #{masked_xpath}#{join_log_lines(log_lines)} - #{reversed_links.length} links")
      next
    end

    if dates
      unique_links_dates = []
      canonical_uris_set_by_date = {}
      links.zip(dates).each do |link, date|
        unless canonical_uris_set_by_date.key?(date)
          canonical_uris_set_by_date[date] = CanonicalUriSet.new([], canonical_equality_cfg)
        end

        unless canonical_uris_set_by_date[date].include?(link.canonical_uri)
          unique_links_dates << [link, date]
          canonical_uris_set_by_date[date] << link.canonical_uri
        end
      end

      if unique_links_dates.length != canonical_uris_set.length
        canonical_urls_dates = canonical_uris
          .zip(dates)
          .map { |canonical_uri, date| [canonical_uri.to_s, date.strftime("%Y-%m-%d")] }
        logger.log("Masked xpath #{masked_xpath} has all links with dates but also duplicates with conflicting dates: #{canonical_urls_dates}")
        next
      end

      sorted_links_dates = sort_links_dates(unique_links_dates)
      sorted_links = sorted_links_dates.map { |link_date| link_date[0] }
      sorted_canonical_uris = sorted_links.map(&:canonical_uri)
      is_sorted_matching_feed = target_feed_entry_canonical_uris
        .zip(sorted_canonical_uris[...target_feed_entry_canonical_uris.length])
        .all? { |uri, entry_uri| canonical_uri_equal?(uri, entry_uri, canonical_equality_cfg) }
      unless is_sorted_matching_feed
        logger.log("Masked xpath #{masked_xpath} has all links with dates but doesn't match feed after sorting")
        sorted_masked_xpath_links_dates_log = sorted_links_dates
          .map { |link_date| [link_date[0].canonical_uri.to_s, link_date[1].strftime("%Y-%m-%d")] }
        logger.log("Masked xpath links with dates: #{sorted_masked_xpath_links_dates_log}")
        logger.log("Feed links: #{target_feed_entry_canonical_uris.map(&:to_s)}")
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
  extractions_by_masked_xpath, feed_entry_canonical_uris, canonical_equality_cfg, page_links, star_count,
  fewer_stars_canonical_uris, min_links_count, logger
)
  logger.log("Trying sorted match with highlighted first link and #{star_count} stars")

  first_link = page_links.find do |page_link|
    canonical_uri_equal?(page_link.canonical_uri, feed_entry_canonical_uris.first, canonical_equality_cfg)
  end
  return nil unless first_link

  best_xpath = nil
  best_links = nil
  extractions_by_masked_xpath.each do |masked_xpath, extraction|
    links_extraction = extraction.links_extraction
    links = links_extraction.links
    canonical_uris = links_extraction.canonical_uris

    next if best_links && best_links.length >= links.length
    next unless links.length >= feed_entry_canonical_uris.length - 1
    next unless links.length >= min_links_count - 1

    is_matching_feed = feed_entry_canonical_uris[1..]
      .zip(canonical_uris[...feed_entry_canonical_uris.length - 1])
      .all? { |xpath_uri, entry_uri| canonical_uri_equal?(xpath_uri, entry_uri, canonical_equality_cfg) }
    is_matching_fewer_stars_links = fewer_stars_canonical_uris &&
      fewer_stars_canonical_uris[1..]
        .zip(canonical_uris[...fewer_stars_canonical_uris.length - 1])
        .all? do |xpath_uri, fewer_stars_uri|
        canonical_uri_equal?(xpath_uri, fewer_stars_uri, canonical_equality_cfg)
      end
    if is_matching_feed && (is_matching_fewer_stars_links || !fewer_stars_canonical_uris)
      best_xpath = masked_xpath
      best_links = links
      logger.log("Masked xpath is good: #{masked_xpath}#{join_log_lines(extraction.log_lines)} (1 + #{links.length} links)")
      next
    end
  end

  if best_links
    SortedResult.new(
      pattern: "archives_2xpaths",
      links: [first_link] + best_links,
      count: 1 + best_links.length,
      has_dates: nil,
      extra: "<br>counts: 1 + #{best_links.length}<br>prefix_xpath: #{first_link.xpath}<br>suffix_xpath: #{best_xpath}",
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
  extractions_by_masked_xpath, feed_entry_canonical_uris, canonical_equality_cfg, feed_generator, page_links,
  min_links_count, logger
)
  logger.log("Trying medium match with pinned entry")

  unless feed_generator == :medium
    logger.log("Feed generator is not Medium")
    return nil
  end

  extractions_by_masked_xpath.each do |masked_xpath, extraction|

    links_extraction = extraction.links_extraction
    links = links_extraction.links
    canonical_uris_set = links_extraction.canonical_uris_set
    medium_markup_dates = extraction.medium_markup_dates

    next unless links.length >= feed_entry_canonical_uris.length - 1
    next unless links.length >= min_links_count - 1
    next unless medium_markup_dates

    feed_uris_not_matching = feed_entry_canonical_uris
      .filter { |entry_uri| !canonical_uris_set.include?(entry_uri) }
    next unless feed_uris_not_matching.length == 1

    pinned_entry_link = page_links.find do |page_link|
      canonical_uri_equal?(page_link.canonical_uri, feed_uris_not_matching.first, canonical_equality_cfg)
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
  prefix_extractions_by_masked_xpath, suffix_extractions_by_masked_xpath, feed_entry_canonical_uris,
  canonical_equality_cfg, star_count, fewer_stars_canonical_uris, min_links_count, logger
)
  logger.log("Trying sorted match with 1+#{star_count} stars")

  feed_prefix_xpaths_by_length = {}
  prefix_extractions_by_masked_xpath.each do |masked_xpath, extraction|
    links = extraction.links_extraction.links
    next if links.length >= feed_entry_canonical_uris.length

    feed_entry_canonical_uris.zip(links).each_with_index do |pair, index|
      feed_entry_canonical_uri, masked_xpath_link = pair
      if index > 0 && masked_xpath_link.nil?
        prefix_length = index
        unless feed_prefix_xpaths_by_length.key?(prefix_length)
          feed_prefix_xpaths_by_length[prefix_length] = []
        end
        feed_prefix_xpaths_by_length[prefix_length] << masked_xpath
        break
      elsif !canonical_uri_equal?(
        feed_entry_canonical_uri, masked_xpath_link.canonical_uri, canonical_equality_cfg
      )
        break # Not a prefix
      end
    end
  end

  best_links = nil
  best_prefix_xpath = nil
  best_suffix_xpath = nil
  best_prefix_count = nil
  best_suffix_count = nil

  suffix_extractions_by_masked_xpath.each do |masked_suffix_xpath, suffix_extraction|
    suffix_links_extraction = suffix_extraction.links_extraction
    suffix_links = suffix_links_extraction.links
    feed_suffix_start_index = feed_entry_canonical_uris.index do |entry_uri|
      canonical_uri_equal?(entry_uri, suffix_links[0].canonical_uri, canonical_equality_cfg)
    end
    next unless feed_suffix_start_index

    is_suffix = true
    feed_entry_canonical_uris[feed_suffix_start_index..]
      .zip(suffix_links)
      .each do |feed_entry_canonical_uri, masked_xpath_link|

      if feed_entry_canonical_uri.nil?
        break # suffix found
      elsif masked_xpath_link.nil?
        is_suffix = false
        break
      elsif !canonical_uri_equal?(
        feed_entry_canonical_uri, masked_xpath_link.canonical_uri, canonical_equality_cfg
      )
        is_suffix = false
        break
      end
    end
    next unless is_suffix

    target_prefix_length = feed_suffix_start_index
    next unless feed_prefix_xpaths_by_length.key?(target_prefix_length)
    total_length = target_prefix_length + suffix_links.length
    next unless total_length >= min_links_count
    next if best_links && total_length <= best_links

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
    combined_canonical_uris = combined_links.map(&:canonical_uri)
    combined_canonical_uris_set = combined_canonical_uris.to_canonical_uri_set(canonical_equality_cfg)
    if combined_canonical_uris.length != combined_canonical_uris_set.length
      logger.log("Combination has all feed links but also duplicates: #{combined_canonical_uris.map(&:to_s)}")
      next
    end

    is_matching_prev_archives_links = !fewer_stars_canonical_uris ||
      fewer_stars_canonical_uris
        .zip(combined_canonical_uris[...fewer_stars_canonical_uris.length])
        .all? do |xpath_uri, fewer_stars_uri|
        canonical_uri_equal?(xpath_uri, fewer_stars_uri, canonical_equality_cfg)
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
  extractions_by_masked_xpath, feed_entry_links, feed_entry_canonical_uris_set,
  canonical_equality_cfg, almost_match_threshold, star_count, fewer_stars_canonical_uris, min_links_count,
  logger
)
  logger.log("Trying almost feed match with #{star_count} stars")

  best_links = nil
  best_xpath = nil

  extractions_by_masked_xpath.each do |masked_xpath, extraction|
    links_extraction = extraction.links_extraction
    links = links_extraction.links
    canonical_uris = links_extraction.canonical_uris
    canonical_uris_set = links_extraction.canonical_uris_set

    next if best_links && best_links.length >= links.length
    next unless links.length >= min_links_count
    next unless links.length < feed_entry_links.length
    next unless links.length >= almost_match_threshold
    next unless feed_entry_links
      .count { |entry_link| canonical_uris_set.include?(entry_link.canonical_uri) } >= almost_match_threshold
    next unless canonical_uris.all? { |uri| feed_entry_canonical_uris_set.include?(uri) }

    is_matching_fewer_stars_links = fewer_stars_canonical_uris &&
      canonical_uris[...fewer_stars_canonical_uris.length]
        .zip(fewer_stars_canonical_uris)
        .all? { |uri, fewer_stars_uri| canonical_uri_equal?(uri, fewer_stars_uri, canonical_equality_cfg) }
    next unless !fewer_stars_canonical_uris || is_matching_fewer_stars_links

    best_links = links
    best_xpath = masked_xpath
    logger.log("Masked xpath almost matches feed: #{masked_xpath}#{join_log_lines(extraction.log_lines)} (#{links.length}/#{feed_entry_links.length} links)")
  end

  if best_links
    SortedResult.new(
      pattern: "feed",
      links: feed_entry_links,
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
  extractions_by_masked_xpath, feed_entry_canonical_uris, canonical_equality_cfg, almost_match_threshold,
  star_count, min_links_count, logger
)
  is_almost = !!almost_match_threshold
  almost_suffix = is_almost ? "_almost" : ""
  logger.log("Trying shuffled#{almost_suffix} match with #{star_count} stars")

  best_links_maybe_dates = nil
  best_xpath = nil

  extractions_by_masked_xpath.each do |masked_xpath, extraction|
    links_extraction = extraction.links_extraction
    links = links_extraction.links
    canonical_uris = links_extraction.canonical_uris
    canonical_uris_set = links_extraction.canonical_uris_set
    maybe_url_dates = extraction.maybe_url_dates

    next if best_links_maybe_dates && best_links_maybe_dates.length >= links.length
    next unless links.length >= feed_entry_canonical_uris.length
    next unless links.length >= min_links_count

    log_lines = extraction.log_lines.clone
    if is_almost
      target_feed_entry_canonical_uris = feed_entry_canonical_uris
        .filter { |entry_uri| canonical_uris_set.include?(entry_uri) }
      next unless target_feed_entry_canonical_uris.length < feed_entry_canonical_uris.length
      next unless target_feed_entry_canonical_uris.length >= almost_match_threshold
      log_lines << "almost feed match #{target_feed_entry_canonical_uris.length}/#{feed_entry_canonical_uris.length}"
    else
      next unless feed_entry_canonical_uris.all? { |entry_uri| canonical_uris_set.include?(entry_uri) }
    end

    links_maybe_url_dates = links.zip(maybe_url_dates)
    if canonical_uris.length != canonical_uris_set.length
      dedup_links_maybe_dates = []
      dedup_canonical_uri_set = CanonicalUriSet.new([], canonical_equality_cfg)
      links_maybe_url_dates.each do |link, maybe_url_date|
        next if dedup_canonical_uri_set.include?(link.canonical_uri)

        dedup_links_maybe_dates << [link, maybe_url_date]
        dedup_canonical_uri_set << link.canonical_uri
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