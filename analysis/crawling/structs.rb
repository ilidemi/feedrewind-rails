Page = Struct.new(:canonical_url, :fetch_uri, :start_link_id, :content_type, :content)
PermanentError = Struct.new(:canonical_url, :fetch_uri, :start_link_id, :code)
Link = Struct.new(:canonical_url, :uri, :url, :type, :xpath, :class_xpath)
