require 'net/http'
require 'set'
require_relative 'util'

HttpResponse = Struct.new(:code, :content_type, :location, :body)

class HttpClient
  def initialize(enable_throttling = true)
    @prev_timestamp = nil
    @enable_throttling = enable_throttling
  end

  def request(uri, _)
    throttle if @enable_throttling

    req = Net::HTTP::Get.new(uri, initheader = { 'User-Agent' => 'Feeduler/0.1' })
    begin
      resp = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
        http.request(req)
      end
    rescue OpenSSL::SSL::SSLError
      return HttpResponse.new("SSLError", nil, nil, nil)
    rescue Errno::ETIMEDOUT
      return HttpResponse.new("Timeout", nil, nil, nil)
    end

    HttpResponse.new(
      resp.code,
      resp.header["content-type"],
      resp.header["location"],
      resp.body
    )
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