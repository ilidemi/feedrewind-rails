require 'net/http'
require 'set'
require_relative 'util'

HttpResponse = Struct.new(:code, :content_type, :location, :body)

class HttpClient
  def initialize(enable_throttling = true)
    @prev_timestamp = nil
    @enable_throttling = enable_throttling
  end

  MAX_CONTENT_LENGTH = 20 * 1024 * 1024

  def request(uri, should_throttle, logger)
    throttle if @enable_throttling && should_throttle

    req = Net::HTTP::Get.new(uri, initheader = { 'User-Agent' => 'FeedRewind.com/0.1 (bot)' })
    begin
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
        http.request(req) do |resp|
          if resp.content_length != nil && resp.content_length > MAX_CONTENT_LENGTH
            return HttpResponse.new("ResponseBodyTooBig", nil, nil, nil)
          end

          total_length = 0
          chunks = []
          resp.read_body do |chunk|
            total_length += chunk.length
            chunks << chunk
            return HttpResponse.new("ResponseBodyTooBig", nil, nil, nil) if total_length > MAX_CONTENT_LENGTH
          end
          body = chunks.join

          return HttpResponse.new(
            resp.code,
            resp.header["content-type"],
            resp.header["location"],
            body
          )
        end
      end
    rescue OpenSSL::SSL::SSLError
      return HttpResponse.new("SSLError", nil, nil, nil)
    rescue Errno::ETIMEDOUT
      return HttpResponse.new("Timeout", nil, nil, nil)
    rescue => error
      logger.info("HTTP request error: #{error}")
      return HttpResponse.new("Exception", nil, nil, nil)
    end
  end

  def get_retry_delay(attempt)
    [1, 5, 15][attempt]
  end

  private

  def throttle
    new_timestamp = monotonic_now
    unless @prev_timestamp.nil?
      time_delta = new_timestamp - @prev_timestamp
      if time_delta < 1.0
        sleep(1.0 - time_delta)
        new_timestamp = monotonic_now
      end
    end
    @prev_timestamp = new_timestamp
  end
end