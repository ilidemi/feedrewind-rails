class GuidedCrawlMockDbStorage
  def initialize(db, start_link_id)
    @db = db
    @page_fetch_urls = db
      .exec_params(
        "select fetch_url, is_from_puppeteer from mock_pages where start_link_id = $1", [start_link_id]
      )
      .map { |row| [row["fetch_url"], row["is_from_puppeteer"] == "t"] }
      .to_set
    @permanent_error_fetch_urls = db
      .exec_params("select fetch_url from mock_permanent_errors where start_link_id = $1", [start_link_id])
      .map { |row| row["fetch_url"] }
      .to_set
    @redirect_fetch_urls = db
      .exec_params("select from_fetch_url from mock_redirects where start_link_id = $1", [start_link_id])
      .map { |row| row["from_fetch_url"] }
      .to_set
  end

  def save_page_if_not_exists(
    canonical_url, fetch_url, content_type, start_link_id, content, is_from_puppeteer
  )
    return if @page_fetch_urls.include?([fetch_url, is_from_puppeteer])
    @page_fetch_urls << [fetch_url, is_from_puppeteer]
    @db.exec_params(
      "insert into mock_pages ("\
        "canonical_url, fetch_url, fetch_time, content_type, start_link_id, content, is_from_puppeteer"\
      ") "\
      "values ($1, $2, now(), $3, $4, $5, $6)",
      [
        canonical_url, fetch_url, content_type, start_link_id, { value: content, format: 1 },
        is_from_puppeteer
      ]
    )
  end

  def save_permanent_error_if_not_exists(canonical_url, fetch_url, start_link_id, code)
    return if @permanent_error_fetch_urls.include?(fetch_url)
    @permanent_error_fetch_urls << fetch_url
    @db.exec_params(
      "insert into mock_permanent_errors (canonical_url, fetch_url, fetch_time, start_link_id, code) "\
      "values ($1, $2, now(), $3, $4)",
      [canonical_url, fetch_url, start_link_id, code]
    )
  end

  def save_redirect_if_not_exists(from_fetch_url, to_fetch_url, start_link_id)
    return if @redirect_fetch_urls.include?(from_fetch_url)
    @redirect_fetch_urls << from_fetch_url
    @db.exec_params(
      "insert into mock_redirects (from_fetch_url, to_fetch_url, fetch_time, start_link_id) "\
      "values ($1, $2, now(), $3)",
      [from_fetch_url, to_fetch_url, start_link_id]
    )
  end
end

class CrawlDbStorage
  def initialize(db, mock_db_storage)
    @db = db
    @mock_db_storage = mock_db_storage
  end

  def save_page(canonical_url, fetch_url, content_type, start_link_id, content, is_from_puppeteer)
    @db.exec_params(
      "insert into pages ("\
        "canonical_url, fetch_url, content_type, start_link_id, content, is_from_puppeteer"\
      ") "\
      "values ($1, $2, $3, $4, $5, $6)",
      [
        canonical_url, fetch_url, content_type, start_link_id, { value: content, format: 1 },
        is_from_puppeteer
      ]
    )
    @mock_db_storage.save_page_if_not_exists(
      canonical_url, fetch_url, content_type, start_link_id, content, is_from_puppeteer
    )
  end

  def save_redirect(from_fetch_url, to_fetch_url, start_link_id)
    @db.exec_params(
      "insert into redirects (from_fetch_url, to_fetch_url, start_link_id) values ($1, $2, $3)",
      [from_fetch_url, to_fetch_url, start_link_id]
    )
    @mock_db_storage.save_redirect_if_not_exists(from_fetch_url, to_fetch_url, start_link_id)
  end

  def save_permanent_error(canonical_url, fetch_url, start_link_id, code)
    @db.exec_params(
      "insert into permanent_errors (canonical_url, fetch_url, start_link_id, code) values ($1, $2, $3, $4)",
      [canonical_url, fetch_url, start_link_id, code]
    )
    @mock_db_storage.save_permanent_error_if_not_exists(canonical_url, fetch_url, start_link_id, code)
  end

  def save_feed(start_link_id, canonical_url)
    page_id = @db.exec_params(
      "select id from pages where start_link_id = $1 and canonical_url = $2",
      [start_link_id, canonical_url]
    )[0]["id"]
    @db.exec_params(
      "insert into feeds (start_link_id, page_id) values ($1, $2)",
      [start_link_id, page_id]
    )
  end
end
