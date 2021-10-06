require_relative '../../app/lib/guided_crawling/puppeteer_client'

class CachingPuppeteerClient
  def initialize(db, start_link_id)
    @db = db
    @start_link_id = start_link_id
    @puppeteer_client = PuppeteerClient.new
  end

  def fetch(link, match_curis_set, crawl_ctx, progress_logger, logger, &find_load_more_button)
    content, document = @puppeteer_client.fetch(
      link, match_curis_set, crawl_ctx, progress_logger, logger, &find_load_more_button
    )

    @db.exec_params(
      "insert into mock_puppeteer_pages (start_link_id, fetch_url, body) values ($1, $2, $3)",
      [@start_link_id, link.url, { value: content, format: 1 }]
    )

    [content, document]
  end
end

class MockPuppeteerClient
  def initialize(db, start_link_id)
    @db = db
    @start_link_id = start_link_id
    @puppeteer_client = CachingPuppeteerClient.new(db, start_link_id)
  end

  def fetch(link, match_curis_set, crawl_ctx, progress_logger, logger, &find_load_more_button)
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
      link, match_curis_set, crawl_ctx, progress_logger, logger, &find_load_more_button
    )
  end
end
