require_relative '../../app/lib/guided_crawling/puppeteer_client'

class CachingPuppeteerClient
  def initialize(db, start_link_id)
    @db = db
    @start_link_id = start_link_id
    @puppeteer_client = PuppeteerClient.new
  end

  def fetch(uri, match_curis_set, crawl_ctx, progress_logger, logger, &find_load_more_button)
    content = @puppeteer_client.fetch(
      uri, match_curis_set, crawl_ctx, progress_logger, logger, &find_load_more_button
    )

    @db.exec_params(
      "insert into mock_puppeteer_pages (start_link_id, fetch_url, body) values ($1, $2, $3)",
      [@start_link_id, uri.to_s, { value: content, format: 1 }]
    )

    content
  end
end

class MockPuppeteerClient
  def initialize(db, start_link_id)
    @db = db
    @start_link_id = start_link_id
    @puppeteer_client = CachingPuppeteerClient.new(db, start_link_id)
  end

  def fetch(uri, match_curis_set, crawl_ctx, progress_logger, logger, &find_load_more_button)
    row = @db.exec_params(
      "select body from mock_puppeteer_pages where start_link_id = $1 and fetch_url = $2",
      [@start_link_id, uri.to_s]
    ).first

    if row
      content = unescape_bytea(row["body"])
      return content
    end

    @puppeteer_client.fetch(
      uri, match_curis_set, crawl_ctx, progress_logger, logger, &find_load_more_button
    )
  end
end
