require_relative 'date_extraction'
require_relative 'page_parsing'
require_relative 'util'

SortState = Struct.new(:dates_by_xpath_source, :page_titles)

def historical_archives_sort_add(page, feed_generator, sort_state, logger)
  logger.info("Archives sort add start")
  page_dates_xpaths_sources = []

  page.document.traverse do |element|
    date_source = try_extract_element_date(element, false)
    next unless date_source

    page_dates_xpaths_sources << {
      xpath: to_canonical_xpath(element.path),
      date: date_source[:date],
      source: date_source[:source]
    }
  end

  page_title = get_page_title(page, feed_generator)

  if sort_state
    page_dates_by_xpath_source = page_dates_xpaths_sources.to_h do |xpath_date_source|
      [[xpath_date_source[:xpath], xpath_date_source[:source]], xpath_date_source[:date]]
    end
    new_sort_state = SortState.new({}, sort_state.page_titles + [page_title])
    sort_state.dates_by_xpath_source.each do |xpath_source, dates|
      next unless page_dates_by_xpath_source.key?(xpath_source)
      new_sort_state.dates_by_xpath_source[xpath_source] = dates + [page_dates_by_xpath_source[xpath_source]]
    end
  else
    dates_by_xpath_source = page_dates_xpaths_sources.to_h do |xpath_date_source|
      [[xpath_date_source[:xpath], xpath_date_source[:source]], [xpath_date_source[:date]]]
    end
    new_sort_state = SortState.new(dates_by_xpath_source, [page_title])
  end

  logger.info("Sort state after #{page.fetch_uri}: #{new_sort_state.dates_by_xpath_source.keys} (#{new_sort_state.page_titles.length} total)")

  if new_sort_state.dates_by_xpath_source.empty?
    if sort_state
      logger.info("Pages don't have a common date path after #{page.fetch_uri}:")
      sort_state.dates_by_xpath_source.each do |xpath_source, dates|
        logger.info("#{xpath_source} -> #{dates.map { |date| date.strftime("%Y-%m-%d") }}")
      end
    else
      logger.info("Page doesn't have a date at #{page.fetch_uri}")
    end
    return nil
  end

  logger.info("Archives sort add finish")
  new_sort_state
end

def historical_archives_sort_finish(links_with_known_dates, links, sort_state, logger)
  logger.info("Archives sort finish start")
  if sort_state
    sort_state.dates_by_xpath_source ||= {}
    dates_by_xpath_from_time = sort_state
      .dates_by_xpath_source
      .filter { |xpath_source, _| xpath_source[1] == :time }
      .map { |xpath_source, dates| [xpath_source[0], dates] }
      .to_h
    if sort_state.dates_by_xpath_source.length == 1
      xpath_source, dates = sort_state.dates_by_xpath_source.first
      logger.info("Good shuffled date xpath_source: #{xpath_source}")
    elsif dates_by_xpath_from_time.length == 1
      xpath, dates = dates_by_xpath_from_time.first
      xpath_source = [xpath, :time]
      logger.info("Good shuffled date xpath from time: #{xpath}")
    else
      logger.info("Couldn't sort links: #{sort_state}")
      return nil
    end

    title_count = 0
    titled_links = links.zip(sort_state.page_titles).map do |link, page_title|
      next link if link.title

      title = create_link_title(page_title, :page_title)
      title_count += 1
      link_set_title(link, title)
    end
    logger.info("Set #{title_count} link titles from page titles")

    links_dates = links_with_known_dates + titled_links.zip(dates)
  else
    links_dates = links_with_known_dates
    xpath_source = "Ø"
  end

  sorted_links_dates = sort_links_dates(links_dates)
  sorted_links = sorted_links_dates.map(&:first)

  logger.info("Archives sort finish finish")
  [sorted_links, xpath_source]
end

def historical_archives_medium_sort_finish(
  pinned_entry_link, pinned_entry_page_links, other_links_dates, curi_eq_cfg
)
  logger.info("Archives medium sort finish start")
  pinned_entry_date = nil
  pinned_entry_page_links.each do |link|
    next unless canonical_uri_equal?(pinned_entry_link.curi, link.curi, curi_eq_cfg)

    link.element.traverse do |child_element|
      next unless child_element.text?

      date = try_extract_text_date(child_element.content, true)
      next unless date

      pinned_entry_date = date
      break
    end

    break if pinned_entry_date
  end

  return nil unless pinned_entry_date

  pinned_entry_link_date = [pinned_entry_link, pinned_entry_date]
  links_dates = [pinned_entry_link_date] + other_links_dates
  sorted_links_dates = sort_links_dates(links_dates)
  sorted_links = sorted_links_dates.map { |link, _| link }

  logger.info("Archives medium sort finish finish")
  sorted_links
end

def sort_links_dates(links_dates)
  # Sort newest to oldest, preserve link order within the same date
  links_dates
    .sort_by
    .with_index { |link_date, index| [link_date[1], -index] }
    .reverse
end