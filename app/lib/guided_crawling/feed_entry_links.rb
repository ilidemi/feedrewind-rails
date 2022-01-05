require_relative 'canonical_link'

class FeedEntryLinks
  def initialize(link_buckets, is_order_certain)
    @link_buckets = link_buckets
    @length = link_buckets.map(&:length).sum
    @is_order_certain = is_order_certain
  end

  attr_reader :link_buckets, :length, :is_order_certain

  def self.from_links_dates(links, dates)
    if dates
      is_order_certain = true
      link_buckets = []
      last_date = nil
      links.zip(dates).each do |link, date|
        if date == last_date
          link_buckets.last << link
        else
          link_buckets << [link]
        end
        last_date = date
      end
    else
      is_order_certain = false
      link_buckets = links.map { |link| [link] }
    end

    FeedEntryLinks.new(link_buckets, is_order_certain)
  end

  def filter_included(curis_set)
    new_link_buckets = []
    @link_buckets.each do |link_bucket|
      new_link_set = link_bucket.filter { |link| curis_set.include?(link.curi) }
      new_link_buckets << new_link_set unless new_link_set.empty?
    end

    FeedEntryLinks.new(new_link_buckets, @is_order_certain)
  end

  def count_included(curis_set)
    @link_buckets
      .map { |link_bucket| link_bucket.count { |link| curis_set.include?(link.curi) } }
      .sum
  end

  def all_included?(curis_set)
    @link_buckets.all? do |link_bucket|
      link_bucket.all? { |link| curis_set.include?(link.curi) }
    end
  end

  def included_prefix_length(curis_set)
    prefix_length = 0
    @link_buckets.each do |link_bucket|
      bucket_included_count = link_bucket.count { |link| curis_set.include?(link.curi) }
      prefix_length += bucket_included_count
      break if bucket_included_count < link_bucket.length
    end

    prefix_length
  end

  def sequence_match(seq_curis, curi_eq_cfg)
    subsequence_match(seq_curis, 0, curi_eq_cfg)
  end

  def subsequence_match(seq_curis, offset, curi_eq_cfg)
    return [] if offset >= length

    current_bucket_index = 0
    while offset >= @link_buckets[current_bucket_index].length
      offset -= @link_buckets[current_bucket_index].length
      current_bucket_index += 1
    end

    remaining_in_bucket = @link_buckets[current_bucket_index].length - offset
    subsequence_links = []
    seq_curis.each do |seq_curi|
      seq_curi_matching_link = @link_buckets[current_bucket_index]
        .find { |bucket_link| canonical_uri_equal?(seq_curi, bucket_link.curi, curi_eq_cfg) }
      return nil unless seq_curi_matching_link

      subsequence_links << seq_curi_matching_link
      remaining_in_bucket -= 1
      if remaining_in_bucket == 0
        current_bucket_index += 1
        break if current_bucket_index >= @link_buckets.length
        remaining_in_bucket = @link_buckets[current_bucket_index].length
      end
    end

    subsequence_links
  end

  def sequence_match_except_first?(seq_curis, curi_eq_cfg)
    return false if @length == 0
    return true if @length == 1

    first_bucket = @link_buckets.first
    if first_bucket.length == 1
      is_match = subsequence_match(seq_curis, 1, curi_eq_cfg)
      if is_match
        return [true, first_bucket.first]
      else
        return [false, nil]
      end
    elsif seq_curis.length < first_bucket.length - 1
      # Feed starts with so many entries of the same date that we run out of sequence and don't know
      # which of the remaining links in the first bucket is the first link
      # We could return several first link candidates but let's keep things simple
      return [false, nil]
    else
      # Compare first bucket separately to see which link is not matching
      first_bucket_remaining = first_bucket.clone
      seq_curis[...(first_bucket.length - 1)].each do |seq_curi|
        match_index = first_bucket_remaining
          .index { |bucket_link| canonical_uri_equal?(seq_curi, bucket_link.curi, curi_eq_cfg) }
        return [false, nil] unless match_index

        first_bucket_remaining.delete_at(match_index)
      end

      is_match = subsequence_match(seq_curis[(first_bucket.length - 1)..], first_bucket.length, curi_eq_cfg)
      if is_match
        return [true, first_bucket_remaining.first]
      else
        return [false, nil]
      end
    end
  end

  def sequence_is_suffix?(seq_curis, curi_eq_cfg)
    return false if seq_curis.empty?

    start_bucket_index = @link_buckets.index do |link_bucket|
      link_bucket.any? { |link| canonical_uri_equal?(link.curi, seq_curis.first, curi_eq_cfg) }
    end
    return false unless start_bucket_index

    start_bucket = @link_buckets[start_bucket_index]
    start_bucket_matching_links = []
    seq_offset = 0
    loop do
      break unless seq_offset < seq_curis.length
      matching_link = start_bucket.find do |link|
        canonical_uri_equal?(link.curi, seq_curis[seq_offset], curi_eq_cfg)
      end
      break unless matching_link

      seq_offset += 1
      start_bucket_matching_links << matching_link
    end

    prefix_length =
      @link_buckets[...start_bucket_index].map(&:length).sum +
        (start_bucket.length - seq_offset)

    matching_links_except_start_bucket = subsequence_match(
      seq_curis[seq_offset..], prefix_length + seq_offset, curi_eq_cfg
    )
    if matching_links_except_start_bucket
      matching_links = start_bucket_matching_links + matching_links_except_start_bucket
      [matching_links, prefix_length]
    else
      [nil, nil]
    end
  end

  def except(curis_set)
    new_link_buckets = []
    @link_buckets.each do |link_bucket|
      new_link_bucket = []
      link_bucket.each do |link|
        next if curis_set.include?(link.curi)

        new_link_bucket << link
      end

      new_link_buckets << new_link_bucket unless new_link_bucket.empty?
    end

    FeedEntryLinks.new(new_link_buckets, @is_order_certain)
  end

  def to_a
    @link_buckets.flatten
  end

  def to_s
    '["' + to_a.map(&:curi).map(&:to_s).join('", "') + '"]'
  end
end
