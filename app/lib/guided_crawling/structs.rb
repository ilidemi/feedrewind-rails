Page = Struct.new(:curi, :fetch_uri, :content, :document)
PermanentError = Struct.new(:curi, :fetch_uri, :code)
Link = Struct.new(:curi, :uri, :url, :element, :xpath, :class_xpath)
HostRedirectConfig = Struct.new(:redirect_from_host, :redirect_to_host, :weird_feed_host)
