require_relative 'date_extraction'
require_relative 'guided_crawling'

def historical_archives_sort_add(page, sort_state, logger)
  page_dates_xpaths_sources = []
  page.document.traverse do |element|
    date_source = try_extract_element_date(element, false)
    next unless date_source

    page_dates_xpaths_sources << {
      xpath: element.path,
      date: date_source[:date],
      source: date_source[:source]
    }
  end

  if sort_state
    page_dates_by_xpath_source = page_dates_xpaths_sources.to_h do |xpath_date_source|
      [[xpath_date_source[:xpath], xpath_date_source[:source]], xpath_date_source[:date]]
    end
    new_sort_state = {}
    sort_state.each do |xpath_source, dates|
      next unless page_dates_by_xpath_source.key?(xpath_source)
      new_sort_state[xpath_source] = dates + [page_dates_by_xpath_source[xpath_source]]
    end
  else
    new_sort_state = page_dates_xpaths_sources.to_h do |xpath_date_source|
      [[xpath_date_source[:xpath], xpath_date_source[:source]], [xpath_date_source[:date]]]
    end
  end

  if new_sort_state.empty?
    logger.log("Pages don't have a common date path after #{page.canonical_uri.to_s}: #{sort_state} -> #{new_sort_state}")
    return nil
  end
  new_sort_state
end

def historical_archives_sort_finish(links, sort_state, logger)
  dates_by_xpath_from_time = sort_state
    .filter_map { |xpath_source, dates| xpath_source[1] == :time ? [xpath_source[0], dates] : nil }
    .to_h
  if sort_state.length == 1
    xpath, dates = sort_state.first
    logger.log("Good shuffled date xpath: #{xpath}")
  elsif dates_by_xpath_from_time.length == 1
    xpath, dates = dates_by_xpath_from_time.first
    logger.log("Good shuffled date xpath from time: #{xpath}")
  else
    return nil
  end

  sorted_links_dates = sort_links_dates(links.zip(dates))
  sorted_links = sorted_links_dates.map { |link, _| link }
  sorted_links
end

def historical_archives_medium_sort_finish(
  pinned_entry_link, pinned_entry_page_links, other_links_dates, canonical_equality_cfg
)
  pinned_entry_date = nil
  pinned_entry_page_links.each do |link|
    next unless canonical_uri_equal?(
      pinned_entry_link.canonical_uri, link.canonical_uri, canonical_equality_cfg
    )

    date = try_extract_text_date(link.element.content, true)
    next unless date

    pinned_entry_date = date
    break
  end

  return nil unless pinned_entry_date

  pinned_entry_link_date = [pinned_entry_link, pinned_entry_date]
  links_dates = [pinned_entry_link_date] + other_links_dates
  sorted_links_dates = sort_links_dates(links_dates)
  sorted_links = sorted_links_dates.map { |link, _| link }
  sorted_links
end

def sort_links_dates(links_dates)
  # Sort newest to oldest, preserve link order within the same date
  links_dates
    .sort_by
    .with_index { |link_date, index| [link_date[1], -index] }
    .reverse
end