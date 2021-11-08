Page = Struct.new(:curi, :fetch_uri, :content, :document)
PermanentError = Struct.new(:curi, :fetch_uri, :code)
Link = Struct.new(:curi, :uri, :url, :title, :element, :xpath, :class_xpath)

def link_fill_title(link, title)
  Link.new(
    link.curi,
    link.uri,
    link.url,
    link.title || title,
    link.element,
    link.xpath,
    link.class_xpath
  )
end

def link_force_title(link, title)
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