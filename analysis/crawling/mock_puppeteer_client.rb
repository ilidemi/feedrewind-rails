class MockPuppeteerClient
  def initialize(db, start_link_id, puppeteer_client)
    @db = db
    @start_link_id = start_link_id
    @puppeteer_client = puppeteer_client
  end

  def fetch(link, match_curis_set, crawl_ctx, logger, &find_load_more_button)
    row = @db.exec_params(
      "select body from mock_puppeteer_pages where start_link_id = $1 and fetch_url = $2",
      [@start_link_id, link.url]
    ).first

    if row
      content = unescape_bytea(row["body"])
      document = nokogiri_html5(content)
      return [content, document]
    end

    @puppeteer_client.fetch(
      link, match_curis_set, crawl_ctx, logger, &find_load_more_button
    )
  end
end
