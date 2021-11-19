Page = Struct.new(:curi, :fetch_uri, :content, :document)
PermanentError = Struct.new(:curi, :fetch_uri, :code)
Link = Struct.new(:curi, :uri, :url, :title, :element, :xpath, :class_xpath)

def link_set_title(link, title)
  Link.new(
    link.curi,
    link.uri,
    link.url,
    title,
    link.element,
    link.xpath,
    link.class_xpath
  )
end