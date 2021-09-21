require_relative '../../app/lib/guided_crawling/http_client'

class MockHttpClient
  def initialize(db, start_link_id)
    @db = db
    @start_link_id = start_link_id
    @http_client = HttpClient.new
    @network_requests_made = 0
  end

  def request(uri, logger)
    fetch_url = uri.to_s

    response_row = @db.exec_params(
      "select code, content_type, location, body from mock_responses where start_link_id = $1 and fetch_url = $2",
      [@start_link_id, fetch_url]
    ).first

    if response_row
      return HttpResponse.new(
        response_row["code"],
        response_row["content_type"],
        response_row["location"],
        unescape_bytea(response_row["body"])
      )
    end

    logger.debug("URI not in mock tables, falling back on http client: #{uri}")
    @network_requests_made += 1
    response = @http_client.request(uri, logger)

    @db.exec_params(
      "insert into mock_responses (start_link_id, fetch_url, code, content_type, location, body) values ($1, $2, $3, $4, $5, $6)",
      [@start_link_id, fetch_url, response.code, response.content_type, response.location, { value: response.body, format: 1 }]
    )

    response
  end

  def get_retry_delay(attempt)
    [0.01, 0.05, 0.15][attempt]
  end

  attr_reader :network_requests_made
end
