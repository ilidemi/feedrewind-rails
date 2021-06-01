def to_canonical_url(uri)
  port_str = (
    uri.port.nil? || (uri.port == 80 && uri.scheme == 'http') || (uri.port == 443 && uri.scheme == 'https')
  ) ? '' : ":#{uri.port}"
  path_str = (uri.path == '/' && uri.query.nil?) ? '' : uri.path
  query_str = uri.query.nil? ? '' : "?#{uri.query}"
  "#{uri.host}#{port_str}#{path_str}#{query_str}" # drop scheme and fragment
end
