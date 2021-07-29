require 'set'
require_relative 'date_extraction'
require_relative 'historical_archives_sort'
require_relative 'historical_common'

def try_extract_archives(
  page, page_links, page_canonical_uris_set, feed_entry_links, feed_entry_canonical_uris,
  feed_entry_canonical_uris_set, feed_generator, canonical_equality_cfg, min_links_count, logger
)
  return nil unless feed_entry_canonical_uris
    .count { |item_uri| page_canonical_uris_set.include?(item_uri) } >=
    almost_match_length(feed_entry_canonical_uris.length)

  logger.log("Possible archives page: #{page.canonical_uri}")
  min_links_count_one_xpath = min_links_count_two_xpaths = min_links_count
  best_historical_result = nil
  best_page_canonical_uris = nil
  fewer_stars_have_dates = false
  best_star_count = nil
  almost_feed_match = nil
  shuffled_full_matches = []
  medium_shuffled_first_link_match = nil

  links_by_masked_xpath_by_star_count = {}
  star_count_xpath_name = [
    [1, :xpath],
    [2, :class_xpath],
    [3, :class_xpath]
  ]

  star_count_xpath_name.each do |star_count, xpath_name|
    logger.log("Trying xpaths with #{star_count} stars")
    historical_result = try_masked_xpath(
      page_links, feed_entry_canonical_uris, feed_entry_canonical_uris_set, feed_generator,
      canonical_equality_cfg, star_count, xpath_name, best_page_canonical_uris, fewer_stars_have_dates,
      min_links_count_one_xpath, min_links_count_two_xpaths, logger
    )

    links_by_masked_xpath_by_star_count[star_count] = historical_result[:links_by_masked_xpath]
    if historical_result[:type] == :full_match
      best_historical_result = historical_result
      best_star_count = star_count.to_s
      if historical_result[:is_one_xpath]
        min_links_count_one_xpath = best_historical_result[:links].length + 1
      else
        min_links_count_one_xpath = best_historical_result[:links].length
      end
      min_links_count_two_xpaths = best_historical_result[:links].length + 1
      best_page_canonical_uris = best_historical_result[:links].map(&:canonical_uri)
      fewer_stars_have_dates = best_historical_result[:has_dates]
    elsif historical_result[:type] == :almost_feed_match
      unless almost_feed_match && almost_feed_match[:length] > historical_result[:length]
        almost_feed_match = historical_result
      end
    elsif historical_result[:type] == :shuffled_full_match
      shuffled_full_matches << historical_result
    elsif historical_result[:type] == :medium_shuffled_first_link_match
      unless medium_shuffled_first_link_match &&
        medium_shuffled_first_link_match[:other_links].length > historical_result[:other_links].length

        medium_shuffled_first_link_match = historical_result
      end
    end
  end

  links_by_masked_xpath_by_star_count.each do |star_count, links_by_masked_xpath|
    logger.log("Trying xpaths with 1+#{star_count} stars")
    historical_result = try_two_masked_xpaths(
      links_by_masked_xpath_by_star_count[1], links_by_masked_xpath, feed_entry_canonical_uris,
      canonical_equality_cfg, best_page_canonical_uris, min_links_count_two_xpaths, logger
    )

    if historical_result
      best_historical_result = historical_result
      best_star_count = "1+#{star_count}"
      min_links_count_two_xpaths = best_historical_result[:links].length + 1
      best_page_canonical_uris = best_historical_result[:links].map(&:canonical_uri)
    end
  end

  result = {}

  better_shuffled_full_matches = shuffled_full_matches.filter do |shuffled_full_match|
    !best_historical_result || shuffled_full_match[:links].length > best_historical_result[:links].length
  end
  unless better_shuffled_full_matches.empty?
    result[:shuffled] = []
    better_shuffled_full_matches.each do |shuffled_full_match|
      logger.log("Shuffled count: #{shuffled_full_match[:links].length}")
      result[:shuffled] << {
        main_canonical_url: page.canonical_uri.to_s,
        main_fetch_url: page.fetch_uri.to_s,
        links: shuffled_full_match[:links],
        pattern: shuffled_full_match[:pattern],
        extra: "star_count: #{best_star_count}#{shuffled_full_match[:extra]}",
        count: shuffled_full_match[:links].length
      }
    end
  end

  if best_historical_result
    logger.log("Best count: #{best_historical_result[:links].length} with #{best_historical_result[:pattern]}")
    result[:sorted] = {
      main_canonical_url: page.canonical_uri.to_s,
      main_fetch_url: page.fetch_uri.to_s,
      links: best_historical_result[:links],
      pattern: best_historical_result[:pattern],
      extra: "star_count: #{best_star_count}#{best_historical_result[:extra]}",
      count: best_historical_result[:links].length
    }
  elsif almost_feed_match
    logger.log("Almost matched feed (#{almost_feed_match[:length]}/#{feed_entry_canonical_uris.length})")
    result[:sorted] = {
      main_canonical_url: page.canonical_uri.to_s,
      main_fetch_url: page.fetch_uri.to_s,
      links: feed_entry_links,
      pattern: "feed",
      extra: "almost_match: #{almost_feed_match[:length]}/#{feed_entry_canonical_uris.length}",
      count: feed_entry_canonical_uris.length
    }
  end

  if medium_shuffled_first_link_match
    links_count = 1 + medium_shuffled_first_link_match[:other_links_dates].length
    logger.log("Medium match with shuffled first link: #{links_count}")
    result[:medium_with_shuffled_first_link] = {
      main_canonical_url: page.canonical_uri.to_s,
      main_fetch_url: page.fetch_uri.to_s,
      pinned_entry_link: medium_shuffled_first_link_match[:pinned_entry_link],
      other_links_dates: medium_shuffled_first_link_match[:other_links_dates],
      pattern: medium_shuffled_first_link_match[:pattern],
      extra: medium_shuffled_first_link_match[:extra],
      count: links_count
    }
  end

  return result unless result.empty?

  logger.log("Not an archives page or the min links count (#{min_links_count}) is not reached")
  nil
end

def almost_match_length(feed_length)
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

def try_masked_xpath(
  page_links, feed_entry_canonical_uris, feed_entry_canonical_uris_set, feed_generator,
  canonical_equality_cfg, star_count, xpath_name, fewer_stars_canonical_uris, fewer_stars_have_dates,
  min_links_count_one_xpath, min_links_count_two_xpaths, logger
)
  links_by_masked_xpath = group_links_by_masked_xpath(
    page_links, feed_entry_canonical_uris_set, xpath_name, star_count
  )
  logger.log("Masked xpaths: #{links_by_masked_xpath.length}")

  # Collapse consecutive duplicates: [a, b, b, c] -> [a, b, c] but [a, b, c, b] -> [a, b, c, b]
  collapsed_links_by_masked_xpath = links_by_masked_xpath.to_h do |masked_xpath, masked_xpath_links|
    collapsed_links = []
    masked_xpath_links.length.times do |index|
      if index == 0 || masked_xpath_links[index].url != masked_xpath_links[index - 1].url
        collapsed_links << masked_xpath_links[index]
      end
    end
    [masked_xpath, collapsed_links]
  end

  # Try to extract dates
  date_extraction_by_masked_xpath = get_date_extraction_by_masked_xpath(
    collapsed_links_by_masked_xpath, feed_entry_canonical_uris, feed_entry_canonical_uris_set,
    canonical_equality_cfg, 0, false
  )

  no_match = {
    type: :no_match,
    links_by_masked_xpath: collapsed_links_by_masked_xpath
  }

  # Try to find the masked xpath that matches all feed entries and covers as many links as possible
  best_xpath = nil
  best_xpath_links = nil
  best_xpath_has_dates = nil
  best_pattern = nil
  almost_feed_match = nil
  shuffled_full_match = nil
  collapsed_links_by_masked_xpath.each do |masked_xpath, masked_xpath_links|
    # If each entry has a date, filter links to ones with dates
    masked_xpath_link_dates = nil
    if date_extraction_by_masked_xpath.key?(masked_xpath)
      date_extraction = date_extraction_by_masked_xpath[masked_xpath]
      filtered_masked_xpath_links = []
      masked_xpath_link_dates = []
      masked_xpath_links.each do |link|
        link_dates = link
          .element
          .xpath(date_extraction.relative_xpath)
          .to_a
          .filter_map { |element| try_extract_element_date(element, false) }
          .map { |date_source| date_source[:date] }
        next if link_dates.empty?

        if link_dates.length > 1
          logger.log("Multiple dates found for #{link.xpath} + #{date_extraction.relative_xpath}: #{link_dates}")
          next
        end

        date = link_dates.first
        next unless date && date <= date_extraction.max_date

        filtered_masked_xpath_links << link
        masked_xpath_link_dates << date
      end

      if filtered_masked_xpath_links.length != masked_xpath_links.length
        logger.log("Filtered links by dates: #{masked_xpath_links.length} -> #{filtered_masked_xpath_links.length}")
        masked_xpath_links = filtered_masked_xpath_links
      end
    else
      next if fewer_stars_have_dates
    end

    # If the set of links is almost covering feed, the feed could be complete with few random links thrown in
    masked_xpath_canonical_uris = masked_xpath_links.map(&:canonical_uri)
    if masked_xpath_links.length < feed_entry_canonical_uris.length &&
      masked_xpath_links.length >= almost_match_length(feed_entry_canonical_uris.length) &&
      masked_xpath_canonical_uris.all? { |uri| feed_entry_canonical_uris_set.include?(uri) } &&
      (!almost_feed_match || almost_feed_match[:length] < masked_xpath_links.length)

      almost_feed_match = {
        type: :almost_feed_match,
        length: masked_xpath_links.length,
        links_by_masked_xpath: collapsed_links_by_masked_xpath
      }
    end

    next if masked_xpath_links.length < feed_entry_canonical_uris.length
    next if masked_xpath_links.length < min_links_count_one_xpath
    next if best_xpath_links && best_xpath_links.length >= masked_xpath_links.length

    masked_xpath_canonical_uris_set = masked_xpath_canonical_uris.to_canonical_uri_set(canonical_equality_cfg)
    next unless feed_entry_canonical_uris
      .all? { |item_uri| masked_xpath_canonical_uris_set.include?(item_uri) }

    masked_xpath_fetch_urls = masked_xpath_links.map(&:url)
    masked_xpath_fetch_urls_set = masked_xpath_fetch_urls.to_set
    has_duplicates = masked_xpath_fetch_urls_set.length != masked_xpath_fetch_urls.length

    is_matching_feed = feed_entry_canonical_uris
      .zip(masked_xpath_canonical_uris[...feed_entry_canonical_uris.length])
      .all? { |xpath_uri, entry_uri| canonical_uri_equal?(xpath_uri, entry_uri, canonical_equality_cfg) }
    is_matching_fewer_stars_links = fewer_stars_canonical_uris &&
      masked_xpath_canonical_uris[...fewer_stars_canonical_uris.length]
        .zip(fewer_stars_canonical_uris)
        .all? do |xpath_uri, fewer_stars_uri|
        canonical_uri_equal?(xpath_uri, fewer_stars_uri, canonical_equality_cfg)
      end
    if is_matching_feed && !has_duplicates && (!fewer_stars_canonical_uris || is_matching_fewer_stars_links)
      best_xpath = masked_xpath
      best_xpath_links = masked_xpath_links
      best_xpath_has_dates = date_extraction_by_masked_xpath.key?(masked_xpath)
      best_pattern = "archives"
      collapsion_log_str = get_collapsion_log_str(masked_xpath, links_by_masked_xpath, collapsed_links_by_masked_xpath)
      dates_log_str = best_xpath_has_dates ? ", dates" : ''
      logger.log("Masked xpath is good: #{masked_xpath}#{collapsion_log_str} (#{masked_xpath_links.length} links#{dates_log_str})")
      next
    end

    reversed_masked_xpath_links = masked_xpath_links.reverse
    reversed_masked_xpath_canonical_uris = masked_xpath_canonical_uris.reverse
    is_reversed_matching_feed = feed_entry_canonical_uris
      .zip(reversed_masked_xpath_canonical_uris[...feed_entry_canonical_uris.length])
      .all? { |xpath_uri, entry_uri| canonical_uri_equal?(xpath_uri, entry_uri, canonical_equality_cfg) }
    is_reversed_matching_fewer_stars_links_prefix = fewer_stars_canonical_uris &&
      reversed_masked_xpath_canonical_uris[...fewer_stars_canonical_uris.length]
        .zip(fewer_stars_canonical_uris)
        .all? do |xpath_uri, fewer_stars_uri|
        canonical_uri_equal?(xpath_uri, fewer_stars_uri, canonical_equality_cfg)
      end
    is_reversed_matching_fewer_stars_links_suffix = fewer_stars_canonical_uris &&
      reversed_masked_xpath_canonical_uris[-fewer_stars_canonical_uris.length..]
        .zip(fewer_stars_canonical_uris)
        .all? do |xpath_uri, fewer_stars_uri|
        canonical_uri_equal?(xpath_uri, fewer_stars_uri, canonical_equality_cfg)
      end
    if is_reversed_matching_feed &&
      !has_duplicates &&
      (!fewer_stars_canonical_uris ||
        is_reversed_matching_fewer_stars_links_prefix ||
        is_reversed_matching_fewer_stars_links_suffix)

      best_xpath = masked_xpath
      best_xpath_links = reversed_masked_xpath_links
      best_xpath_has_dates = date_extraction_by_masked_xpath.key?(masked_xpath)
      best_pattern = "archives"
      collapsion_log_str = get_collapsion_log_str(
        masked_xpath, links_by_masked_xpath, collapsed_links_by_masked_xpath
      )
      dates_log_str = best_xpath_has_dates ? ", dates" : ''
      logger.log("Masked xpath is good in reverse order: #{masked_xpath}#{collapsion_log_str} (#{reversed_masked_xpath_links.length} links#{dates_log_str})")
      next
    end

    if masked_xpath_link_dates
      masked_xpath_links_dates = masked_xpath_links
        .zip(masked_xpath_link_dates)
        .uniq { |link, date| [link.url, date] }
      if masked_xpath_links_dates.length != masked_xpath_fetch_urls_set.length
        masked_xpath_canonical_urls_dates = masked_xpath_canonical_uris
          .zip(masked_xpath_link_dates)
          .map { |canonical_uri, date| [canonical_uri.to_s, date.strftime("%Y-%m-%d")] }
        logger.log("Masked xpath #{masked_xpath} has all links with dates but also duplicates with conflicting dates: #{masked_xpath_canonical_urls_dates}")
        next
      end

      best_xpath = masked_xpath
      best_xpath_links_dates = sort_links_dates(masked_xpath_links_dates)
      best_xpath_links = best_xpath_links_dates.map { |link_date| link_date[0] }
      best_xpath_has_dates = true
      best_pattern = "archives_shuffled"
      collapsion_log_str = get_collapsion_log_str(
        masked_xpath, links_by_masked_xpath, collapsed_links_by_masked_xpath
      )
      newest_date = best_xpath_links_dates.first[1]
      oldest_date = best_xpath_links_dates.last[1]
      logger.log("Masked xpath is good sorted by date: #{masked_xpath}#{collapsion_log_str} (#{masked_xpath_links.length} links from #{oldest_date} to #{newest_date})")
      next
    end

    if has_duplicates
      dedup_masked_xpath_links = []
      dedup_masked_xpath_canonical_uri_set = CanonicalUriSet.new([], canonical_equality_cfg)
      masked_xpath_links.each do |link|
        next if dedup_masked_xpath_canonical_uri_set.include?(link.canonical_uri)

        dedup_masked_xpath_links << link
        dedup_masked_xpath_canonical_uri_set << link.canonical_uri
      end
    else
      dedup_masked_xpath_links = masked_xpath_links
    end

    if !fewer_stars_canonical_uris ||
      (dedup_masked_xpath_links.length > fewer_stars_canonical_uris.length &&
        (is_matching_fewer_stars_links ||
          is_reversed_matching_fewer_stars_links_prefix ||
          is_reversed_matching_fewer_stars_links_suffix)
      )

      collapsion_log_str = get_collapsion_log_str(
        masked_xpath, links_by_masked_xpath, collapsed_links_by_masked_xpath
      )
      dedup_log_str = dedup_masked_xpath_links.length > masked_xpath_links.length ?
        " (dedup #{masked_xpath_links.length} -> #{dedup_masked_xpath_links.length})" :
        ""
      logger.log("Masked xpath is good but shuffled: #{masked_xpath}#{collapsion_log_str}#{dedup_log_str} (#{masked_xpath_links.length} links)")
      shuffled_full_match = {
        type: :shuffled_full_match,
        pattern: "archives_shuffled",
        links: masked_xpath_links,
        extra: "<br>xpath: #{best_xpath}",
        links_by_masked_xpath: collapsed_links_by_masked_xpath
      }
      next
    end

    logger.log("Masked xpath #{masked_xpath} has all links")
    logger.log("#{feed_entry_canonical_uris.map(&:to_s)}")
    logger.log("but not in the right order:")
    logger.log("#{masked_xpath_canonical_uris.map(&:to_s)}")
    logger.log("and/or not matching fewer stars links:")
    logger.log("#{fewer_stars_canonical_uris.map(&:to_s)}")
  end

  if best_xpath_links
    return {
      type: :full_match,
      pattern: best_pattern,
      links: best_xpath_links,
      has_dates: best_xpath_has_dates,
      extra: "<br>xpath: #{best_xpath}",
      links_by_masked_xpath: collapsed_links_by_masked_xpath
    }
  end

  if feed_entry_canonical_uris.length < 3
    return almost_feed_match if almost_feed_match
    return no_match
  end

  # Try to see if the first post doesn't match due to being decorated somehow but other strictly fit
  # Don't do almost feed matching or reverse matching
  # Do shuffled matching and Medium dates matching
  first_link = page_links.find do |page_link|
    canonical_uri_equal?(page_link.canonical_uri, feed_entry_canonical_uris.first, canonical_equality_cfg)
  end
  medium_shuffled_first_link_match = nil
  if first_link
    medium_date_extraction_by_masked_xpath = get_date_extraction_by_masked_xpath(
      collapsed_links_by_masked_xpath, feed_entry_canonical_uris, feed_entry_canonical_uris_set,
      canonical_equality_cfg, 1, true
    )
    best_xpath_without_first = nil
    best_xpath_links_without_first = nil
    collapsed_links_by_masked_xpath.each do |masked_xpath, masked_xpath_links|
      next if masked_xpath_links.length < feed_entry_canonical_uris.length - 1
      next if masked_xpath_links.length < min_links_count_two_xpaths - 1
      next if best_xpath_links && best_xpath_links.length >= masked_xpath_links.length + 1
      next if best_xpath_links_without_first &&
        best_xpath_links_without_first.length >= masked_xpath_links.length

      masked_xpath_canonical_uris = masked_xpath_links.map(&:canonical_uri)
      is_matching_feed = feed_entry_canonical_uris[1..]
        .zip(masked_xpath_canonical_uris[...feed_entry_canonical_uris.length - 1])
        .all? { |xpath_uri, entry_uri| canonical_uri_equal?(xpath_uri, entry_uri, canonical_equality_cfg) }
      is_matching_fewer_stars_links = fewer_stars_canonical_uris &&
        fewer_stars_canonical_uris[1..]
          .zip(masked_xpath_canonical_uris[...fewer_stars_canonical_uris.length - 1])
          .all? do |xpath_uri, fewer_stars_uri|
          canonical_uri_equal?(xpath_uri, fewer_stars_uri, canonical_equality_cfg)
        end
      if is_matching_feed && (is_matching_fewer_stars_links || !fewer_stars_canonical_uris)
        collapsion_log_str = get_collapsion_log_str(
          masked_xpath, links_by_masked_xpath, collapsed_links_by_masked_xpath
        )
        logger.log("Masked xpath is good: #{masked_xpath}#{collapsion_log_str} (1 + #{masked_xpath_links.length} links)")
        best_xpath_without_first = masked_xpath
        best_xpath_links_without_first = masked_xpath_links
        next
      end

      if feed_generator == :medium && medium_date_extraction_by_masked_xpath.key?(masked_xpath)
        masked_xpath_canonical_uris_set = masked_xpath_canonical_uris
          .to_canonical_uri_set(canonical_equality_cfg)
        feed_uris_not_matching = feed_entry_canonical_uris
          .filter { |entry_uri| !masked_xpath_canonical_uris_set.include?(entry_uri) }
        next unless feed_uris_not_matching.length == 1

        pinned_entry_link = page_links.find do |page_link|
          canonical_uri_equal?(page_link.canonical_uri, feed_uris_not_matching.first, canonical_equality_cfg)
        end
        next unless pinned_entry_link

        date_extraction = medium_date_extraction_by_masked_xpath[masked_xpath]
        other_links_dates = masked_xpath_links.filter_map do |link|
          link_dates = link
            .element
            .xpath(date_extraction.relative_xpath)
            .to_a
            .filter_map { |element| try_extract_element_date(element, true) }
            .map { |date_source| date_source[:date] }
          next nil if link_dates.empty?

          if link_dates.length > 1
            logger.log("Multiple dates found for #{link.xpath} + #{date_extraction.relative_xpath}: #{link_dates}")
            next nil
          end

          date = link_dates.first
          next nil unless date && date <= date_extraction.max_date

          [link, date]
        end

        if other_links_dates.length != masked_xpath_links.length
          logger.log("Not all Medium links have dates")
          next
        end

        collapsion_log_str = get_collapsion_log_str(
          masked_xpath, links_by_masked_xpath, collapsed_links_by_masked_xpath
        )
        logger.log("Masked xpath is good but shuffled: #{masked_xpath}#{collapsion_log_str} (1 + #{other_links_dates.length} links)")
        medium_shuffled_first_link_match = {
          type: :medium_shuffled_first_link_match,
          pattern: "archives_shuffled_2xpaths",
          pinned_entry_link: pinned_entry_link,
          other_links_dates: other_links_dates,
          extra: "<br>counts: 1 + #{masked_xpath_links.length}<br>prefix_xpath: #{pinned_entry_link.xpath}<br>suffix_xpath: #{masked_xpath}",
          links_by_masked_xpath: collapsed_links_by_masked_xpath
        }
      end

    end

    if best_xpath_links_without_first
      return {
        type: :full_match,
        pattern: "archives_2xpaths",
        links: [first_link] + best_xpath_links_without_first,
        extra: "<br>counts: 1 + #{best_xpath_links_without_first.length}<br>prefix_xpath: #{first_link.xpath}<br>suffix_xpath: #{best_xpath_without_first}",
        links_by_masked_xpath: collapsed_links_by_masked_xpath
      }
    end
  end

  return almost_feed_match if almost_feed_match
  return shuffled_full_match if shuffled_full_match
  return medium_shuffled_first_link_match if medium_shuffled_first_link_match
  no_match
end

DateExtraction = Struct.new(:relative_xpath, :max_date)

def get_date_extraction_by_masked_xpath(
  links_by_masked_xpath, feed_entry_canonical_uris, feed_entry_canonical_uris_set, canonical_equality_cfg,
  allowed_non_matches, guess_year
)
  date_extraction_by_masked_xpath = {}
  links_by_masked_xpath.each do |masked_xpath, masked_xpath_links|
    masked_xpath_links_matching_feed = masked_xpath_links
      .filter { |link| feed_entry_canonical_uris_set.include?(link.canonical_uri) }
    masked_xpath_canonical_uris_matching_feed_set = masked_xpath_links_matching_feed
      .map(&:canonical_uri)
      .to_canonical_uri_set(canonical_equality_cfg)
    next unless masked_xpath_canonical_uris_matching_feed_set.length ==
      feed_entry_canonical_uris.length - allowed_non_matches

    last_star_index = masked_xpath.rindex("*")
    link_ancestors_till_star = masked_xpath[last_star_index..].count("/")
    relative_xpath_to_top_parent = "/.." * link_ancestors_till_star
    date_relative_xpaths_sources = []
    max_date = nil
    masked_xpath_links_matching_feed.each_with_index do |link, index|
      link_top_parent = link.element
      link_ancestors_till_star.times do
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
        if date_source[:date]
          link_date_relative_xpaths_sources << relative_xpath_source

          if !max_date || date_source[:date] > max_date
            max_date = date_source[:date]
          end
        end
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
      next
    end

    date_extraction_by_masked_xpath[masked_xpath] = DateExtraction.new(date_relative_xpath, max_date)
  end

  date_extraction_by_masked_xpath
end

def try_two_masked_xpaths(
  prefix_links_by_masked_xpath, suffix_links_by_masked_xpath, feed_entry_canonical_uris,
  canonical_equality_cfg, prev_archives_canonical_uris, min_links_count, logger
)
  feed_prefix_xpaths_by_length = {}
  prefix_links_by_masked_xpath.each do |masked_xpath, masked_xpath_links|
    next if masked_xpath_links.length >= feed_entry_canonical_uris.length

    feed_entry_canonical_uris.zip(masked_xpath_links).each_with_index do |pair, index|
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

  suffix_links_by_masked_xpath.each do |masked_suffix_xpath, masked_suffix_xpath_links|
    feed_suffix_start_index = feed_entry_canonical_uris.index do |entry_uri|
      canonical_uri_equal?(entry_uri, masked_suffix_xpath_links[0].canonical_uri, canonical_equality_cfg)
    end
    next unless feed_suffix_start_index

    is_suffix = true
    feed_entry_canonical_uris[feed_suffix_start_index..]
      .zip(masked_suffix_xpath_links)
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
    total_length = target_prefix_length + masked_suffix_xpath_links.length
    next unless total_length >= min_links_count

    masked_prefix_xpath = feed_prefix_xpaths_by_length[target_prefix_length][0]
    masked_prefix_xpath_links = prefix_links_by_masked_xpath[masked_prefix_xpath]

    # Ensure the first suffix link appears on the page after the last prefix link
    # Find the lowest common parent and see if prefix parent comes before suffix parent
    last_prefix_link = masked_prefix_xpath_links.last
    first_suffix_link = masked_suffix_xpath_links.first
    # Link can't be a parent of another link. Not actually expecting that but just in case
    next if last_prefix_link.element == first_suffix_link.element.parent ||
      first_suffix_link.element == last_prefix_link.element.parent
    prefix_parent_id_to_self_and_child = {}
    current_prefix_element = last_prefix_link.element
    while current_prefix_element.element? do
      prefix_parent_id_to_self_and_child[current_prefix_element.parent.pointer_id] =
        [current_prefix_element.parent, current_prefix_element]
      current_prefix_element = current_prefix_element.parent
    end
    top_suffix_element = first_suffix_link.element
    while top_suffix_element.element? &&
      !prefix_parent_id_to_self_and_child.key?(top_suffix_element.parent.pointer_id) do

      top_suffix_element = top_suffix_element.parent
    end
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

    logger.log("Found partition with two xpaths: #{target_prefix_length} + #{masked_suffix_xpath_links.length}")
    # Skipping collapsion log because it is minor and happened in a different func
    logger.log("Prefix xpath: #{masked_prefix_xpath}")
    logger.log("Suffix xpath: #{masked_suffix_xpath}")

    combined_links = masked_prefix_xpath_links + masked_suffix_xpath_links
    combined_canonical_uris = combined_links.map(&:canonical_uri)
    combined_canonical_uris_set = combined_canonical_uris.to_canonical_uri_set(canonical_equality_cfg)
    if combined_canonical_uris.length != combined_canonical_uris_set.length
      logger.log("Combination has all feed links but also duplicates: #{combined_canonical_uris.map(&:to_s)}")
      next
    end

    is_matching_prev_archives_links = !prev_archives_canonical_uris ||
      prev_archives_canonical_uris
        .zip(combined_canonical_uris[...prev_archives_canonical_uris.length])
        .all? do |xpath_uri, fewer_stars_uri|
        canonical_uri_equal?(xpath_uri, fewer_stars_uri, canonical_equality_cfg)
      end
    unless is_matching_prev_archives_links
      logger.log("Combination doesn't match previous archives links")
      next
    end

    logger.log("Combination is good")
    return {
      pattern: "archives_2xpaths",
      links: combined_links,
      extra: "<br>counts: #{target_prefix_length} + #{masked_suffix_xpath_links.length}<br>prefix_xpath: #{masked_prefix_xpath}<br>suffix_xpath: #{masked_suffix_xpath}"
    }
  end

  nil
end
