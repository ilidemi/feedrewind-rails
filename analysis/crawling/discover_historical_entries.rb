require 'set'

def discover_historical_entries(start_link_id, feed_item_urls, allowed_hosts, redirects, db, logger)
  logger.log("Discover historical entries started")

  db.transaction do |transaction|
    transaction.exec_params(
      "declare pages_cursor cursor for select canonical_url, fetch_url, content_type, content from pages where start_link_id = $1 and content is not null",
      [start_link_id]
    )

    loop do
      rows = transaction.exec("fetch next from pages_cursor")
      if rows.cmd_tuples == 0
        break
      end

      row = rows[0]
      page = { canonical_url: row["canonical_url"], fetch_uri: URI(row["fetch_url"]), content_type: row["content_type"], content: unescape_bytea(row["content"]) }
      page_links = extract_links(page, allowed_hosts, redirects, logger, include_xpath = true)
      allowed_urls = page_links[:allowed_host_links]
        .map { |link| link[:canonical_url] }
        .to_set
      if feed_item_urls.all? { |item_url| allowed_urls.include?(item_url) }
        logger.log("Found archives page: #{page[:canonical_url]}")

        links_by_masked_xpath = {}
        page_links[:allowed_host_links].each do |page_link|
          match_datas = page_link[:xpath].to_enum(:scan, /\[\d+\]/).map { Regexp.last_match }
          match_datas.each do |match_data|
            start, finish = match_data.offset(0)
            masked_xpath = page_link[:xpath][0..start] + '*' + page_link[:xpath][(finish - 1)..-1]
            unless links_by_masked_xpath.key?(masked_xpath)
              links_by_masked_xpath[masked_xpath] = []
            end
            links_by_masked_xpath[masked_xpath] << page_link
          end
        end
        logger.log("Masked xpaths: #{links_by_masked_xpath.length}")

        links_by_masked_xpath.each do |masked_xpath, links|
          next if links.length < feed_item_urls.length

          link_urls = links.map { |link| link[:canonical_url] }.to_set
          if feed_item_urls.all? { |item_url| link_urls.include?(item_url) }
            logger.log("The masked xpath: #{masked_xpath}")
            return { archive_url: page[:fetch_uri].to_s, links: links }
          end
        end
      end
    end
  end

  nil
end
