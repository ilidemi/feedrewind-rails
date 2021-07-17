require 'net/http'
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

    req = Net::HTTP::Get.new(uri, initheader = { 'User-Agent' => 'rss-catchup/0.1' })
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

class MockJitHttpClient
  def initialize(db, start_link_id)
    @db = db
    @start_link_id = start_link_id
    @http_client = HttpClient.new
    @network_requests_made = 0
  end

  def request(uri, logger)
    fetch_url = uri.to_s

    page_row = @db.exec_params(
      "select content_type, content from mock_pages where start_link_id = $1 and fetch_url = $2",
      [@start_link_id, fetch_url]
    ).first

    if page_row
      return HttpResponse.new("200", page_row["content_type"], nil, unescape_bytea(page_row["content"]))
    end

    permanent_error_row = @db.exec_params(
      "select code from mock_permanent_errors where start_link_id = $1 and fetch_url = $2",
      [@start_link_id, fetch_url]
    ).first

    if permanent_error_row
      return HttpResponse.new(permanent_error_row["code"], nil, nil, "Mock permanent error content")
    end

    redirect_row = @db.exec_params(
      "select to_fetch_url from mock_redirects where start_link_id = $1 and from_fetch_url = $2",
      [@start_link_id, fetch_url]
    ).first

    if redirect_row
      return HttpResponse.new("301", nil, redirect_row["to_fetch_url"], "Mock redirect content")
    end

    logger.log("URI not in mock tables, falling back on http client: #{uri}")
    @network_requests_made += 1
    @http_client.request(uri, logger)
  end

  attr_reader :network_requests_made
end