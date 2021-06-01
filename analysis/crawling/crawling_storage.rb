class CrawlDbStorage
  def initialize(db)
    @db = db
  end

  def save_page(canonical_url, fetch_url, content_type, start_link_id, content)
    @db.exec_params(
      'insert into pages (canonical_url, fetch_url, content_type, start_link_id, content) values ($1, $2, $3, $4, $5)',
      [canonical_url, fetch_url, content_type, start_link_id, content]
    )
  end

  def delete_redirect(from_canonical_url, start_link_id)
    @db.exec_params(
      'delete from redirects where from_canonical_url = $1 and start_link_id = $2',
      [from_canonical_url, start_link_id]
    )
  end

  def save_redirect(from_canonical_url, to_canonical_url, to_fetch_url, start_link_id)
    @db.exec_params(
      'insert into redirects (from_canonical_url, to_canonical_url, to_fetch_url, start_link_id) values ($1, $2, $3, $4)',
      [from_canonical_url, to_canonical_url, to_fetch_url, start_link_id]
    )
  end

  def save_permanent_error(canonical_url, fetch_url, start_link_id, code)
    @db.exec_params(
      'insert into permanent_errors (canonical_url, fetch_url, start_link_id, code) values ($1, $2, $3, $4)',
      [canonical_url, fetch_url, start_link_id, code]
    )
  end

  def save_feed(start_link_id, canonical_url)
    @db.exec_params(
      'insert into feeds (start_link_id, canonical_url) values ($1, $2)',
      [start_link_id, canonical_url]
    )
  end
end

class CrawlInMemoryStorage
  def initialize
    @pages = {}
    @redirects = {}
    @permanent_errors = {}
    @feeds = {}
  end

  def save_page(canonical_url, fetch_url, content_type, start_link_id, content)
    save_or_raise(
      @pages, canonical_url,
      { canonical_url: canonical_url, fetch_url: fetch_url, content_type: content_type, start_link_id: start_link_id, content: content }
    )
  end

  def delete_redirect(from_canonical_url, _)
    unless @redirects.delete(from_canonical_url)
      raise "Redirect was not found: #{from_canonical_url}"
    end
  end

  def save_redirect(from_canonical_url, to_canonical_url, to_fetch_url, start_link_id)
    save_or_raise(
      @redirects, from_canonical_url,
      { from_canonical_url: from_canonical_url, to_canonical_url: to_canonical_url, to_fetch_url: to_fetch_url, start_link_id: start_link_id }
    )
  end

  def save_permanent_error(canonical_url, fetch_url, start_link_id, code)
    save_or_raise(
      @permanent_errors, canonical_url,
      { canonical_url: canonical_url, fetch_url: fetch_url, start_link_id: start_link_id, code: code }
    )
  end

  def save_feed(start_link_id, canonical_url)
    save_or_raise(
      @feeds, start_link_id,
      { start_link_id: start_link_id, canonical_url: canonical_url }
    )
  end

  attr_reader :pages, :redirects, :permanent_errors, :feeds

  private

  def save_or_raise(hash, key, value)
    if hash.key?(key)
      raise "Key already present: #{key}"
    end

    hash[key] = value
  end
end
