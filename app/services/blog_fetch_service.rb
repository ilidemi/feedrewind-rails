require 'date'
require 'net/http'
require 'nokogiri'
require 'nokogumbo'
require 'set'
require 'uri'
require 'yaml'

module BlogFetchService
  Post = Struct.new(:link, :title, :date)

  def self.get_relative_xpath(child_xpath, parent_xpath)
    raise "#{child_xpath} is not a child of #{parent_xpath}" unless child_xpath.start_with?(parent_xpath)
    child_tokens = child_xpath.split('/')
    parent_tokens = parent_xpath.split('/')
    child_rel_tokens = child_tokens[parent_tokens.length + 1..]
    "./#{child_rel_tokens.join('/')}"
  end

  def self.to_absolute_uri(link, parent_uri)
    URI(link).scheme.nil? ? parent_uri + link : link
  end

  def BlogFetchService.fetch(url, list_xpath, link_xpath, title_xpath, date_xpath)
    link_rel_xpath = get_relative_xpath(link_xpath, list_xpath)
    title_rel_xpath = get_relative_xpath(title_xpath, list_xpath)
    date_rel_xpath = get_relative_xpath(date_xpath, list_xpath)

    posts = []
    list_uri = URI(url)
    headers = { 'User-Agent': 'RSS-Catchup-Crawler/0.1' }
    Net::HTTP.start(list_uri.host, list_uri.port, headers: headers, use_ssl: list_uri.scheme == 'https') do |http|
      page_uri = list_uri
      visited_urls = Set.new
      loop do
        visited_urls.add(page_uri)
        list_request = Net::HTTP::Get.new(page_uri)
        list_response = http.request(list_request)
        list_response.value
        list_html = Nokogiri.HTML5(list_response.body)
        list = list_html.at_xpath(list_xpath)
        page_posts = []
        list.children.each do |post|
          next unless post.is_a?(Nokogiri::XML::Element)

          post_link_element = post.at_xpath(link_rel_xpath)
          next if post_link_element.nil?

          post_link = post_link_element['href']
          next if post_link.nil?

          # if post_filter_xpath and post_filter_length
          #   post_filter_text_element = post.at_xpath(post_filter_xpath)
          #   post_filter_text = post_filter_text_element.content
          #   next if post_filter_text.length < post_filter_length
          # end

          post_absolute_link = to_absolute_uri(post_link, page_uri)
          post_title_element = post.at_xpath(title_rel_xpath)
          post_title = post_title_element ? post_title_element.inner_text.strip : post_absolute_link
          post_date_element = post.at_xpath(date_rel_xpath)
          post_date = post_date_element.inner_text.strip
          page_posts << Post.new(post_absolute_link, post_title, post_date)
        end

        # if blog['is_page_chronological']
        #   page_posts.reverse!
        # end
        posts.append(*page_posts)

        break # unless blog.include?('next_page_xpath')

        # next_page_element = list_html.at_xpath(blog['next_page_xpath'])
        # next_page_link = next_page_element['href']
        # break unless next_page_link
        #
        # page_uri = to_absolute_uri(next_page_link, page_uri)
        # break if visited_urls.include?(page_uri)
        #
        # sleep(0.5)
      end
    end

    raise "Couldn't fetch any posts" if posts.empty?

    posts
  end

  private_class_method :get_relative_xpath, :to_absolute_uri
end
