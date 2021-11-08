Page = Struct.new(:curi, :fetch_uri, :content, :document)
PermanentError = Struct.new(:curi, :fetch_uri, :code)
Link = Struct.new(:curi, :uri, :url, :title, :title_xpath, :element, :xpath, :class_xpath)

def link_fill_title(link, title, title_xpath)
  return link if link.title

  Link.new(
    link.curi,
    link.uri,
    link.url,
    title,
    title_xpath,
    link.element,
    link.xpath,
    link.class_xpath
  )
end

def link_force_title(link, title, title_xpath)
  Link.new(
    link.curi,
    link.uri,
    link.url,
    title,
    title_xpath,
    link.element,
    link.xpath,
    link.class_xpath
  )
end