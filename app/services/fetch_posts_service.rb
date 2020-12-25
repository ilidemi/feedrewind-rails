require 'date'
require 'net/http'
require 'nokogiri'
require 'nokogumbo'
require 'set'
require 'uri'
require 'yaml'

module FetchPostsService
  Post = Struct.new(:link, :title, :date)
  FetchParams = Struct.new(:url, :list_xpath, :link_xpath, :title_xpath, :date_xpath, :paging, :filtering)
  PagingParams = Struct.new(:next_page_xpath, :page_order)
  FilteringParams = Struct.new(:length_filter_xpath, :min_length)
  FetchPagedParams = Struct.new(
    :list_xpath, :link_rel_xpath, :title_rel_xpath, :date_rel_xpath, :paging, :filtering)
  FilteringRelParams = Struct.new(:length_filter_rel_xpath, :min_length)

  def FetchPostsService.fetch(params)
    link_rel_xpath = get_relative_xpath(params.link_xpath, params.list_xpath)
    title_rel_xpath = get_relative_xpath(params.title_xpath, params.list_xpath)
    date_rel_xpath = get_relative_xpath(params.date_xpath, params.list_xpath)
    length_filter_rel_xpath = params.filtering ?
      get_relative_xpath(params.filtering.length_filter_xpath, params.list_xpath) :
      nil
    filtering_rel_params = params.filtering ?
      FilteringRelParams.new(length_filter_rel_xpath, params.filtering.min_length) :
      nil

    posts = []
    list_uri = URI(params.url)
    headers = { 'User-Agent': 'RSS-Catchup-Crawler/0.1' }
    Net::HTTP.start(list_uri.host, list_uri.port, headers: headers, use_ssl: list_uri.scheme == 'https') do |http|
      list_request = Net::HTTP::Get.new(list_uri)
      list_response = http.request(list_request)
      list_response.value
      list_html = Nokogiri.HTML5(list_response.body)
      posts = self.extract_posts(
        list_html, list_uri, params.list_xpath, link_rel_xpath, title_rel_xpath, date_rel_xpath, filtering_rel_params)
      if params.paging and params.paging.page_order == 'oldest_first'
        posts.reverse!
      end
    end

    raise "Couldn't fetch any posts" if posts.empty?

    posts.reverse!

    paged_params = params.paging ?
      FetchPagedParams.new(
        params.list_xpath, link_rel_xpath, title_rel_xpath, date_rel_xpath, params.paging, filtering_rel_params) :
      nil
    { posts: posts, paged_params: paged_params }
  end

  def FetchPostsService.fetch_paged(blog_url, paged_params, &save_posts)
    list_uri = URI(blog_url)
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

        page_posts = self.extract_posts(
          list_html, page_uri, paged_params.list_xpath, paged_params.link_rel_xpath, paged_params.title_rel_xpath,
          paged_params.date_rel_xpath, paged_params.filtering)

        if paged_params.paging.page_order == 'newest_first'
          page_posts.reverse!
        end

        save_posts.call(page_posts)

        next_page_element = list_html.at_xpath(paged_params.paging.next_page_xpath)
        next_page_link = next_page_element['href']
        break unless next_page_link

        page_uri = to_absolute_uri(next_page_link, page_uri)
        break if visited_urls.include?(page_uri)

        sleep(0.5)
      end
    end
  end

  def self.extract_posts(
    list_html, page_uri, list_xpath, link_rel_xpath, title_rel_xpath, date_rel_xpath, filtering_rel_params
  )
    list = list_html.at_xpath(list_xpath)
    page_posts = []
    list.children.each do |post|
      next unless post.is_a?(Nokogiri::XML::Element)

      post_link_element = post.at_xpath(link_rel_xpath)
      next if post_link_element.nil?

      post_link = post_link_element['href']
      next if post_link.nil?

      if filtering_rel_params
        length_filter_text_element = post.at_xpath(filtering_rel_params.length_filter_rel_xpath)
        length_filter_text = length_filter_text_element.content
        next if length_filter_text.length < filtering_rel_params.min_length
      end

      post_absolute_link = to_absolute_uri(post_link, page_uri)
      post_title_element = post.at_xpath(title_rel_xpath)
      post_title = post_title_element ? post_title_element.inner_text.strip : post_absolute_link
      post_date_element = post.at_xpath(date_rel_xpath)
      post_date = post_date_element.inner_text.strip
      page_posts << FetchPostsService::Post.new(post_absolute_link, post_title, post_date)
    end

    page_posts
  end

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

  private_class_method :get_relative_xpath, :to_absolute_uri, :extract_posts
end
