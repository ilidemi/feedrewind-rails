require_relative 'historical_common'

class ArchivesCategoriesState
  def initialize
    @links_maybe_dates_by_feed_matching_curis_set = {}
  end

  attr_reader :links_maybe_dates_by_feed_matching_curis_set
end

ArchivesCategoriesResult = Struct.new(
  :main_link, :pattern, :links_maybe_dates, :speculative_count, :count, :extra,
  keyword_init: true
)
CategoryResult = Struct.new(:links_maybe_dates, :xpath, :level, :curi, :fetch_uri, keyword_init: true)

def try_extract_archives_categories(
  page_link, page, page_curis_set, feed_entry_links, feed_entry_curis_set,
  extractions_by_masked_xpath_by_star_count, state, curi_eq_cfg, logger
)
  return nil unless feed_entry_links.count_included(page_curis_set) >= 2

  # Assuming all links in the feed are unique for simpler merging of categories
  return nil unless feed_entry_links.length == feed_entry_curis_set.length

  logger.info("Trying to match archives categories")

  best_links_maybe_dates = nil
  best_feed_matching_curis_set = nil
  best_xpath = nil

  extractions_by_masked_xpath_by_star_count.each do |star_count, extractions_by_masked_xpath|
    logger.info("Trying category match with #{star_count} stars")

    extractions_by_masked_xpath.each do |masked_xpath, extraction|
      links_extraction = extraction.links_extraction
      links = links_extraction.links

      next if best_links_maybe_dates && best_links_maybe_dates.length >= links.length
      next unless links.length >= 2

      feed_matching_curis_set = feed_entry_links
        .filter_included(links_extraction.curis_set)
        .to_a
        .map(&:curi)
        .to_canonical_uri_set(curi_eq_cfg)
      next unless feed_matching_curis_set.length >= 2
      next unless feed_matching_curis_set.length <= feed_entry_links.length - 2

      maybe_dates = extraction
        .maybe_url_dates
        .zip(extraction.some_markup_dates || [])
        .map { |maybe_url_date, maybe_markup_date| maybe_url_date || maybe_markup_date }
      links_maybe_dates = links.zip(maybe_dates)
      log_lines = extraction.log_lines.clone
      if links_extraction.curis.length != links_extraction.curis_set.length
        dedup_links_maybe_dates = []
        dedup_curis_set = CanonicalUriSet.new([], curi_eq_cfg)
        links_maybe_dates.each do |link, maybe_date|
          next if dedup_curis_set.include?(link.curi)

          dedup_links_maybe_dates << [link, maybe_date]
          dedup_curis_set << link.curi
        end
        log_lines << "dedup #{links.length} -> #{dedup_links_maybe_dates.length}"
      else
        dedup_links_maybe_dates = links_maybe_dates
      end

      best_links_maybe_dates = dedup_links_maybe_dates
      best_feed_matching_curis_set = feed_matching_curis_set
      best_xpath = masked_xpath
      logger.info("Masked xpath looks like a category: #{masked_xpath}#{join_log_lines(log_lines)} (#{feed_matching_curis_set.length} links matching feed, #{dedup_links_maybe_dates.length} total)")
    end
  end

  unless best_links_maybe_dates
    logger.info("No archives categories match")
    return nil
  end

  state_hash = state.links_maybe_dates_by_feed_matching_curis_set
  if !state_hash.key?(best_feed_matching_curis_set) ||
    state_hash[best_feed_matching_curis_set].links_maybe_dates.length < best_links_maybe_dates.length

    level = page.curi.trimmed_path&.count("/") || 0
    state_hash[best_feed_matching_curis_set] = CategoryResult.new(
      links_maybe_dates: best_links_maybe_dates,
      xpath: best_xpath,
      level: level,
      curi: page.curi,
      fetch_uri: page.fetch_uri
    )
  end

  almost_match_threshold = get_archives_categories_almost_match_threshold(feed_entry_links.length)

  combinations_count = 0
  state_hash.to_a.combination(2).each do |feed_matching_curis_sets_categories|
    combinations_count += 1
    result = try_combination(
      feed_matching_curis_sets_categories, feed_entry_links, curi_eq_cfg, almost_match_threshold,
      combinations_count, page_link, logger
    )
    return result if result
  end

  state_hash.to_a.combination(3).each do |feed_matching_curis_sets_categories|
    combinations_count += 1
    result = try_combination(
      feed_matching_curis_sets_categories, feed_entry_links, curi_eq_cfg, almost_match_threshold,
      combinations_count, page_link, logger
    )
    return result if result
  end

  logger.info("No archives categories match. Combinations checked: #{combinations_count}")

  nil
end

def get_archives_categories_almost_match_threshold(feed_length)
  if feed_length <= 9
    feed_length
  elsif feed_length <= 19
    feed_length - 1
  else
    feed_length - 2
  end
end

def try_combination(
  feed_matching_curis_sets_categories, feed_entry_links, curi_eq_cfg, almost_match_threshold,
  combinations_count, main_link, logger
)
  feed_matching_curis_sets = feed_matching_curis_sets_categories.map(&:first)
  categories = feed_matching_curis_sets_categories.map(&:last)
  return nil unless categories.map(&:level).to_set.length == 1

  sum_length = feed_matching_curis_sets.map(&:length).sum
  return nil unless sum_length >= almost_match_threshold

  merged_feed_matching_curis_set = CanonicalUriSet.new(feed_matching_curis_sets.first.curis, curi_eq_cfg)
  feed_matching_curis_sets[1..].each do |feed_matching_curis_set|
    merged_feed_matching_curis_set.merge!(feed_matching_curis_set.curis)
  end
  return nil unless merged_feed_matching_curis_set.length >= almost_match_threshold

  if merged_feed_matching_curis_set.length < feed_entry_links.length
    missing_links_maybe_dates = feed_entry_links
      .to_a
      .filter { |entry_link| !merged_feed_matching_curis_set.include?(entry_link.curi) }
      .map { |entry_link| [entry_link, nil] }
    almost_suffix = "_almost"
  else
    missing_links_maybe_dates = []
    almost_suffix = ""
  end

  merged_links_maybe_dates = categories.map(&:links_maybe_dates).flatten(1) + missing_links_maybe_dates

  unique_links_maybe_dates = []
  curis_set = CanonicalUriSet.new([], curi_eq_cfg)
  merged_links_maybe_dates.each do |link, maybe_date|
    next if curis_set.include?(link.curi)

    curis_set << link.curi
    unique_links_maybe_dates << [link, maybe_date]
  end

  log_lines = []
  if merged_links_maybe_dates.length != unique_links_maybe_dates.length
    log_lines << "dedup #{merged_links_maybe_dates.length} -> #{unique_links_maybe_dates.length}"
  end
  logger.info("Found match with #{categories.length} categories#{join_log_lines(log_lines)} (#{unique_links_maybe_dates.length} links total)")
  feed_matching_curis_sets_categories.each_with_index do |feed_matching_curis_set_category, index|
    feed_matching_curis_set, category = feed_matching_curis_set_category
    logger.info("Category #{index + 1}: url #{category.curi}, masked xpath #{category.xpath}, feed count #{feed_matching_curis_set.length}, total count #{category.links_maybe_dates.length}")
  end
  logger.info("Missing links: #{missing_links_maybe_dates.length}")
  logger.info("Combinations checked: #{combinations_count}")

  extra_lines = []
  feed_matching_curis_sets_categories.each_with_index do |feed_matching_curis_set_category, index|
    feed_matching_curis_set, category = feed_matching_curis_set_category
    extra_lines << "cat#{index + 1}_url: <a href=\"#{category.fetch_uri}\">#{category.curi}</a>"
    extra_lines << "cat#{index + 1}_xpath: #{category.xpath}"
    extra_lines << "cat#{index + 1}_feed_count: #{feed_matching_curis_set.length}"
    extra_lines << "cat#{index + 1}_total_count: #{category.links_maybe_dates.length}"

  end
  extra_lines << "missing_count: #{missing_links_maybe_dates.length}"

  ArchivesCategoriesResult.new(
    main_link: main_link,
    pattern: "archives_categories#{almost_suffix}",
    links_maybe_dates: unique_links_maybe_dates,
    speculative_count: unique_links_maybe_dates.length,
    count: nil,
    extra: extra_lines.join("<br>")
  )
end