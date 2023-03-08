module ApplicationHelper
  def icon_tags
    [
      tag("link", { rel: "icon", sizes: "32x32", href: "/favicon_32x32.png" }),
      tag("link", { rel: "icon", sizes: "48x48", href: "/favicon_48x48.png" }),
      tag("link", { rel: "icon", sizes: "96x96", href: "/favicon_96x96.png" }),
      tag("link", { rel: "icon", sizes: "192x192", href: "/favicon_192x192.png" }),
      tag("link", { rel: "apple-touch-icon", href: "/apple-touch-icon.png" }),
    ].join("\n").html_safe
  end
end
