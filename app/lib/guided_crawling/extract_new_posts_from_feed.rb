require_relative 'feed_parsing'
require_relative 'canonical_link'

def extract_new_posts_from_feed(
  feed_content, feed_uri, existing_post_curis, discarded_feed_entry_urls, curi_eq_cfg, logger,
  parse_feed_logger
)
  existing_post_curis_set = existing_post_curis.to_canonical_uri_set(curi_eq_cfg)

  discarded_feed_entry_curis = discarded_feed_entry_urls.map { |url| to_canonical_link(url, logger).curi }
  discarded_feed_entry_curis_set = discarded_feed_entry_curis.to_canonical_uri_set(curi_eq_cfg)

  parsed_feed = parse_feed(feed_content, feed_uri, parse_feed_logger)
  feed_entry_links = parsed_feed.entry_links.except(discarded_feed_entry_curis_set)
  feed_entry_links_list = feed_entry_links.to_a
  new_posts_count = feed_entry_links_list.count do |feed_link|
    !existing_post_curis_set.include?(feed_link.curi)
  end
  return [] if new_posts_count == 0

  overlapping_posts_count = feed_entry_links.length - new_posts_count
  if overlapping_posts_count < 3
    logger.info("Can't update from feed because the overlap with existing posts isn't long enough")
    return nil
  end

  # Not checking if entry_links.is_order_certain because this suffix check is similar but doesn't require
  # the feed to have dates
  feed_matching_links, _ = feed_entry_links.sequence_is_suffix?(existing_post_curis, curi_eq_cfg)
  unless feed_matching_links
    logger.info("Can't update from feed because the existing posts don't match")
    return nil
  end

  # Protects from feed out of order as without it feed [6] [1] [2] [3] [4] [5] would still find suffix in
  # existing posts [2 3 4 5 6]
  unless feed_matching_links.length == overlapping_posts_count
    logger.info("Can't update from feed because the existing posts match but the count is wrong")
    return nil
  end

  feed_entry_links_list[...new_posts_count]
end
