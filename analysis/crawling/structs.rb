Page = Struct.new(
  :canonical_uri, :fetch_uri, :start_link_id, :content_type, :content, :document, :is_puppeteer_used
)
PermanentError = Struct.new(:canonical_uri, :fetch_uri, :start_link_id, :code)
Link = Struct.new(:canonical_uri, :uri, :url, :type, :xpath, :class_xpath)
HostRedirectConfig = Struct.new(:redirect_from_host, :redirect_to_host, :weird_feed_host)
