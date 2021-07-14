require 'addressable/uri'
require_relative 'structs'

def to_canonical_link(url, logger, fetch_uri = nil)
  url_stripped = url
    .sub(/\A( |\t|\n|\x00|\v|\f|\r|%20|%09|%0a|%00|%0b|%0c|%0d)+/i, '')
    .sub(/( |\t|\n|\x00|\v|\f|\r|%20|%09|%0a|%00|%0b|%0c|%0d)+\z/i, '')
  url_newlines_removed = url_stripped.delete("\n")

  if !/\A(http(s)?:)?[\-_.!~*'()a-zA-Z\d;\/?&=+$,]+\z/.match?(url_newlines_removed)
    begin
      url_unescaped = Addressable::URI.unescape(url_newlines_removed)
      unless url_unescaped.valid_encoding?
        url_unescaped = url_newlines_removed
      end
      return nil if url_unescaped.start_with?(":")
      url_escaped = Addressable::URI.escape(url_unescaped)
    rescue Addressable::URI::InvalidURIError => e
      if e.message.include?("Invalid character in host") ||
        e.message.include?("Invalid port number") ||
        e.message.include?("Invalid scheme format") ||
        e.message.include?("Absolute URI missing hierarchical segment")

        logger.log("Invalid URL: \"#{url}\" from \"#{fetch_uri}\" has #{e}")
        return nil
      else
        raise
      end
    end
  else
    url_escaped = url_newlines_removed
  end

  return nil if url_escaped.start_with?("mailto:")

  begin
    uri = URI(url_escaped)
  rescue URI::InvalidURIError => e
    logger.log("Invalid URL: \"#{url}\" from \"#{fetch_uri}\" has #{e}")
    return nil
  end

  if uri.scheme.nil? && !fetch_uri.nil? # Relative uri
    fetch_uri_classes = { 'http' => URI::HTTP, 'https' => URI::HTTPS }
    path = URI::join(fetch_uri, uri).path
    uri = fetch_uri_classes[fetch_uri.scheme].build(host: fetch_uri.host, path: path, query: uri.query)
  end

  return nil unless %w[http https].include? uri.scheme

  uri.fragment = nil
  if uri.userinfo != nil
    logger.log("Invalid URL: \"#{uri}\" from \"#{fetch_uri}\" has userinfo: #{uri.userinfo}")
    return nil
  end
  if uri.opaque != nil
    logger.log("Invalid URL: \"#{uri}\" from \"#{fetch_uri}\" has opaque: #{uri.opaque}")
    return nil
  end
  if uri.registry != nil
    raise "URI has extra parts: #{uri} registry:#{uri.registry}"
  end

  uri.path = uri.path.gsub("//", "/")
  uri.query = uri.query&.gsub("+", "%2B")

  canonical_uri = CanonicalUri.from_uri(uri)
  Link.new(canonical_uri, uri, uri.to_s)
end

class CanonicalUri
  WHITELISTED_QUERY_PARAMS = Set.new(
    [
      "page",
      "year",
      "m", # month (apenwarr)
      "start",
      "offset",
      "skip",
      "updated-max", # blogspot
      "sort",
      "order",
      "format"
    ]
  )

  WHITELISTED_QUERY_PARAM_REGEX = /.*page/ # freshpaint

  def initialize(host, port, path, query)
    @host = host
    @port = port
    @path = path
    @query = query
  end

  def self.from_uri(uri)
    if uri.port.nil? || (uri.port == 80 && uri.scheme == 'http') || (uri.port == 443 && uri.scheme == 'https')
      port = ''
    else
      port = ":#{uri.port}"
    end

    if uri.path == '/' && uri.query.nil?
      path = ''
    else
      path = uri.path
    end

    if uri.query
      whitelisted_query = uri
        .query
        .split("&")
        .map { |token| token.partition("=") }
        .filter { |param, _, _| WHITELISTED_QUERY_PARAMS.include?(param) || WHITELISTED_QUERY_PARAM_REGEX.match?(param) }
        .map { |param, equals, value| equals.empty? ? param : value.empty? ? "#{param}=" : "#{param}=#{value}" }
        .join("&")
      query = whitelisted_query.empty? ? '' : "?#{whitelisted_query}"
    else
      query = ''
    end

    CanonicalUri.new(uri.host, port, path, query)
  end

  def self.from_db_string(db_str)
    dummy_uri = URI("http://#{db_str}")
    CanonicalUri.from_uri(dummy_uri)
  end

  def to_s
    "#{@host}#{@port}#{@path}#{@query}"
  end

  def ==(other)
    raise "Equality check for CanonicalUris is not supported, please use the standalone function"
  end

  attr_reader :host, :port, :path, :query
end

CanonicalEqualityConfig = Struct.new(:same_hosts, :expect_tumblr_paths)

def trim_trailing_slashes(path)
  trailing_slash_count = 0
  while path[-trailing_slash_count - 1] == '/' do
    trailing_slash_count += 1
  end
  path[0..-trailing_slash_count - 1]
end

def canonical_uri_same_path?(canonical_uri1, canonical_uri2)
  path1 = canonical_uri1.path
  path2 = canonical_uri2.path
  path1 == path2 || trim_trailing_slashes(path1) == trim_trailing_slashes(path2)
end

TUMBLR_PATH_REGEX = "^(/post/\\d+)(?:/[^/]+)?/?$"

def canonical_uri_equal?(canonical_uri1, canonical_uri2, canonical_equality_cfg)
  same_hosts = canonical_equality_cfg.same_hosts
  host1 = canonical_uri1.host
  host2 = canonical_uri2.host
  return false unless host1 == host2 || (same_hosts.include?(host1) && same_hosts.include?(host2))

  if canonical_equality_cfg.expect_tumblr_paths
    tumblr_match1 = canonical_uri1.path.match(TUMBLR_PATH_REGEX)
    tumblr_match2 = canonical_uri2.path.match(TUMBLR_PATH_REGEX)
    return true if tumblr_match1 && tumblr_match2 && tumblr_match1[1] == tumblr_match2[1]
  end
  return false unless canonical_uri_same_path?(canonical_uri1, canonical_uri2)

  canonical_uri1.query == canonical_uri2.query
end

class CanonicalUriSet
  def initialize(canonical_uris, canonical_equality_cfg)
    @canonical_equality_cfg = canonical_equality_cfg
    @canonical_uris = []
    @paths_queries_by_server = {}
    @length = 0
    merge!(canonical_uris)
  end

  def add(canonical_uri)
    server = canonical_uri.host + canonical_uri.port
    server_key = @canonical_equality_cfg.same_hosts.include?(server) ? :same_hosts : server
    unless @paths_queries_by_server.key?(server_key)
      @paths_queries_by_server[server_key] = {}
    end

    queries_by_trimmed_path = @paths_queries_by_server[server_key]
    trimmed_path = trim_path(canonical_uri.path)
    unless queries_by_trimmed_path.key?(trimmed_path)
      queries_by_trimmed_path[trimmed_path] = Set.new
    end

    return if queries_by_trimmed_path[trimmed_path].include?(canonical_uri.query)

    queries_by_trimmed_path[trimmed_path] << canonical_uri.query
    @canonical_uris << canonical_uri
    @length += 1
  end

  def <<(item)
    add(item)
  end

  def include?(canonical_uri)
    server = canonical_uri.host + canonical_uri.port
    server_key = @canonical_equality_cfg.same_hosts.include?(server) ? :same_hosts : server
    trimmed_path = trim_path(canonical_uri.path)
    @paths_queries_by_server.key?(server_key) &&
      @paths_queries_by_server[server_key].key?(trimmed_path) &&
      @paths_queries_by_server[server_key][trimmed_path].include?(canonical_uri.query)
  end

  def merge!(canonical_uris)
    canonical_uris.each do |canonical_uri|
      add(canonical_uri)
    end
  end

  def update_equality_config(canonical_equality_cfg)
    canonical_uris = @canonical_uris
    @canonical_equality_cfg = canonical_equality_cfg
    @canonical_uris = []
    @paths_queries_by_server = {}
    @length = 0
    merge!(canonical_uris)
  end

  attr_reader :length

  private

  def trim_path(path)
    if @canonical_equality_cfg.expect_tumblr_paths
      tumblr_match = path.match(TUMBLR_PATH_REGEX)
      return tumblr_match[1] if tumblr_match
    end

    trim_trailing_slashes(path)
  end
end

module Enumerable
  def to_canonical_uri_set(canonical_equality_cfg)
    CanonicalUriSet.new(self, canonical_equality_cfg)
  end
end
