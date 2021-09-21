Page = Struct.new(
  :curi, :fetch_uri, :start_link_id, :content_type, :content, :document, :is_puppeteer_used
)
PermanentError = Struct.new(:curi, :fetch_uri, :start_link_id, :code)
Link = Struct.new(:curi, :uri, :url, :element, :xpath, :class_xpath)
HostRedirectConfig = Struct.new(:redirect_from_host, :redirect_to_host, :weird_feed_host)
