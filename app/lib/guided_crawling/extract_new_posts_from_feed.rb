require_relative 'feed_parsing'
require_relative 'canonical_link'

def extract_new_posts_from_feed(
  feed_content, feed_uri, existing_post_urls, discarded_feed_entry_urls, curi_eq_cfg, logger
)
  existing_post_curis = existing_post_urls.map { |url| to_canonical_link(url, logger).curi }
  existing_post_curis_set = existing_post_curis.to_canonical_uri_set(curi_eq_cfg)

  discarded_feed_entry_curis = discarded_feed_entry_urls.map { |url| to_canonical_link(url, logger).curi }
  discarded_feed_entry_curis_set = discarded_feed_entry_curis.to_canonical_uri_set(curi_eq_cfg)

  parsed_feed = parse_feed(feed_content, feed_uri, logger)
  feed_entry_links = parsed_feed.entry_links.except(discarded_feed_entry_curis_set)
  feed_entry_links_list = feed_entry_links.to_a
  new_posts_count = feed_entry_links_list.count do |feed_link|
    !existing_post_curis_set.include?(feed_link.curi)
  end
  return [] if new_posts_count == 0

  overlapping_posts_count = feed_entry_links.length - new_posts_count
  return nil if overlapping_posts_count < 3

  # Not checking if entry_links.is_order_certain because this suffix check is similar but doesn't require
  # the feed to have dates
  feed_matching_links, _ = feed_entry_links.sequence_is_suffix?(existing_post_curis, curi_eq_cfg)
  return nil unless feed_matching_links

  # Protects from feed out of order as without it feed [6] [1] [2] [3] [4] [5] would still find suffix in
  # existing posts [2 3 4 5 6]
  return nil unless feed_matching_links.length == overlapping_posts_count

  # If there are 3 new posts and the feed buckets are [1] [2] [3 4], we only need to ensure [1] and [2] are
  # solitary, [3] can be inferred
  are_new_posts_orderable = feed_entry_links
    .link_buckets[...new_posts_count - 1]
    .all? { |link_bucket| link_bucket.length == 1 }
  return nil unless are_new_posts_orderable

  # Resolve the [3 4] situation
  last_new_post_link = feed_entry_links
    .link_buckets[new_posts_count - 1]
    .find { |feed_link| !existing_post_curis_set.include?(feed_link.curi) }

  feed_entry_links_list[...new_posts_count - 1] + [last_new_post_link]
end
