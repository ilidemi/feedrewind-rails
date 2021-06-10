require 'set'
require_relative 'db'
require_relative 'util'

HttpResponse = Struct.new(:code, :content_type, :location, :body)

class HttpClient
  def initialize
    @prev_timestamp = nil
  end

  def request(uri, _)
    throttle

    req = Net::HTTP::Get.new(uri)
    resp = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
      http.request(req)
    end

    HttpResponse.new(
      resp.code,
      resp.header["content-type"],
      resp.header["location"],
      resp.body
    )
  end

  private

  def throttle
    new_timestamp = monotonic_now
    unless @prev_timestamp.nil?
      time_delta = new_timestamp - @prev_timestamp
      if time_delta < 1.0
        sleep(1.0 - time_delta)
        new_timestamp = monotonic_now
      end
    end
    @prev_timestamp = new_timestamp
  end
end

class MockHttpClient
  def initialize(db, start_link_id)
    @page_responses = db.exec_params(
      "select fetch_url, content_type, content from mock_pages where start_link_id = $1",
      [start_link_id]
    ).to_h do |page_row|
      [
        page_row["fetch_url"],
        HttpResponse.new("200", page_row["content_type"], nil, unescape_bytea(page_row["content"]))
      ]
    end

    @page_fetch_urls = Set.new(@page_responses.keys)

    @permanent_error_responses = db.exec_params(
      "select fetch_url, code from mock_permanent_errors where start_link_id = $1",
      [start_link_id]
    ).to_h do |permanent_error_row|
      [
        permanent_error_row["fetch_url"],
        HttpResponse.new(permanent_error_row["code"], nil, nil, "Mock permanent error content")
      ]
    end

    @permanent_error_fetch_urls = Set.new(@permanent_error_responses.keys)

    @redirect_responses = db.exec_params(
      "select from_fetch_url, to_fetch_url from mock_redirects where start_link_id = $1",
      [start_link_id]
    ).to_h do |redirect_row|
      [
        redirect_row["from_fetch_url"],
        HttpResponse.new("301", nil, redirect_row["to_fetch_url"], "Mock redirect content")
      ]
    end

    @redirect_fetch_urls = Set.new(@redirect_responses.keys)

    @http_client = HttpClient.new
    @network_requests_made = 0
  end

  def request(uri, logger)
    fetch_url = uri.to_s
    if @page_responses.key?(fetch_url)
      return @page_responses[fetch_url]
    end

    if @permanent_error_responses.key?(fetch_url)
      return @permanent_error_responses[fetch_url]
    end

    if @redirect_responses.key?(fetch_url)
      return @redirect_responses[fetch_url]
    end

    logger.log("URI not in mock tables, falling back on http client: #{uri}")
    @network_requests_made += 1
    @http_client.request(uri, logger)
  end

  attr_reader :page_fetch_urls, :permanent_error_fetch_urls, :redirect_fetch_urls, :network_requests_made
end