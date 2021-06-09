require_relative '../analysis/crawling/crawling'
require_relative '../analysis/crawling/logger'

def canonical_link(url, canonical_url)
  uri = URI(url)
  { canonical_url: canonical_url, host: uri.host, uri: uri, url: url }
end

test_data = [
  # ["description", %w[url fetch_url], %w[expected_url expected_canonical_url]]
  ["should parse absolute http url", %w[http://ya.ru/hi http://ya.ru], %w[http://ya.ru/hi ya.ru/hi]],
  ["should parse absolute https url", %w[https://ya.ru/hi https://ya.ru], %w[https://ya.ru/hi ya.ru/hi]],
  ["should ignore non-http(s) url", %w[ftp://ya.ru/hi ftp://ya.ru], nil],
  ["should parse relative url", %w[20201227 https://apenwarr.ca/log/], %w[https://apenwarr.ca/log/20201227 apenwarr.ca/log/20201227]],
  ["should parse relative url with /", %w[/abc https://ya.ru/hi/hello], %w[https://ya.ru/abc ya.ru/abc]],
  ["should parse relative url with ./", %w[./abc https://ya.ru/hi/hello], %w[https://ya.ru/hi/abc ya.ru/hi/abc]],
  ["should parse relative url with ../", %w[../abc https://ya.ru/hi/hello/bonjour], %w[https://ya.ru/hi/abc ya.ru/hi/abc]],
  ["should parse relative url with //", %w[//ya.ru/abc https://ya.ru/hi/hello], %w[https://ya.ru/abc ya.ru/abc]],
  ["should drop fragment", %w[https://ya.ru/abc#def https://ya.ru], %w[https://ya.ru/abc ya.ru/abc]],
  ["should include non-standard port in canonical url", %w[https://ya.ru:444/abc https://ya.ru:444], %w[https://ya.ru:444/abc ya.ru:444/abc]],
  ["should drop standard http port in canonical url", %w[http://ya.ru:80/abc http://ya.ru:80], %w[http://ya.ru/abc ya.ru/abc]],
  ["should drop standard https port in canonical url", %w[https://ya.ru:443/abc https://ya.ru:443], %w[https://ya.ru/abc ya.ru/abc]],
  ["should include whitelisted query in canonical url", %w[https://ya.ru/abc?blog=1&page=2 https://ya.ru], %w[https://ya.ru/abc?blog=1&page=2 ya.ru/abc?blog=1&page=2]],
  ["should include whitelisted query without value in canonical url", %w[https://ya.ru/abc?blog https://ya.ru], %w[https://ya.ru/abc?blog ya.ru/abc?blog]],
  ["should include whitelisted query with empty value in canonical url", %w[https://ya.ru/abc?blog= https://ya.ru], %w[https://ya.ru/abc?blog= ya.ru/abc?blog=]],
  ["should remove non-whitelisted query in canonical url", %w[https://ya.ru/abc?a=1&b=2 https://ya.ru], %w[https://ya.ru/abc?a=1&b=2 ya.ru/abc]],
  ["should include only whitelisted query in canonical url", %w[https://ya.ru/abc?blog=1&b=2 https://ya.ru], %w[https://ya.ru/abc?blog=1&b=2 ya.ru/abc?blog=1]],
  ["should drop root path from canonical url if no query", %w[https://ya.ru/ https://ya.ru/], %w[https://ya.ru/ ya.ru]],
  ["should keep root path in canonical url if query", %w[https://ya.ru/?blog https://ya.ru/], %w[https://ya.ru/?blog ya.ru/?blog]],
  ["should ignore newlines", %W[https://ya.ru/ab\nc https://ya.ru/], %w[https://ya.ru/abc ya.ru/abc]],
  ["should trim leading and trailing spaces", [" https://ya.ru ", "https://ya.ru"], %w[https://ya.ru ya.ru]],
  ["should trim leading and trailing escaped spaces", ["%20https://waitbutwhy.com/table/like-improve-android-phone%20", "https://waitbutwhy.com/table/like-improve-iphone"], %w[https://waitbutwhy.com/table/like-improve-android-phone waitbutwhy.com/table/like-improve-android-phone]],
  ["should trim leading and trailing escaped crazy whitespace", [" \t\n\x00\v\f\r%20%09%0a%00%0b%0c%0d%0A%0B%0C%0Dhttps://ya.ru \t\n\x00\v\f\r%20%09%0a%00%0b%0c%0d%0A%0B%0C%0D", "https://ya.ru"], %w[https://ya.ru ya.ru]],
  ["should escape middle spaces", ["/tagged/alex norris", "https://webcomicname.com/post/652255218526011392/amp"], %w[https://webcomicname.com/tagged/alex%20norris webcomicname.com/tagged/alex%20norris]],
  ["should ignore invalid character in host", ["http://targetWindow.postMessage(message, targetOrigin, [transfer]);", "https://thewitchofendor.com/2019/02/20/"], nil],
  ["should ignore invalid port number", %w[http://localhost:${port}` https://medium.com/samsung-internet-dev/hello-deno-ed1f8961be26?source=post_internal_links---------2----------------------------], nil],
  ["should ignore url with userinfo", ["http://npm install phaser@3.15.1", "https://thewitchofendor.com/2019/01/page/2/"], nil],
  ["should ignore url with opaque", %w[http:mgd1981.wordpress.com/2012/06/11/truth-in-spectacles-and-speculation-in-tentacles/#NoSpoilers https://thefatalistmarksman.com/page/2/], nil],
  ["should ignore url with invalid scheme format", %w[(https://github.com/facebook/react/) https://dev.to/t/react], nil],
  ["should ignore url with missing hierarchical segment", %w[http: https://ai.googleblog.com/2017/11/], nil],
  ["should ignore mailto url", %w[mailto:aras_at_nesnausk_dot_org https://aras-p.info/toys/game-industry-rumor.php], nil],
  ["should escape url", %w[https://ya.ru/Россия https://ya.ru], %w[https://ya.ru/%D0%A0%D0%BE%D1%81%D1%81%D0%B8%D1%8F ya.ru/%D0%A0%D0%BE%D1%81%D1%81%D0%B8%D1%8F]],
  ["should preserve escaped url", %w[https://ya.ru/%D0%A0%D0%BE%D1%81%D1%81%D0%B8%D1%8F https://ya.ru], %w[https://ya.ru/%D0%A0%D0%BE%D1%81%D1%81%D0%B8%D1%8F ya.ru/%D0%A0%D0%BE%D1%81%D1%81%D0%B8%D1%8F]],
  ["should handle half-escaped url", %w[https://ya.ru/Рос%D1%81%D0%B8%D1%8F% https://ya.ru], %w[https://ya.ru/%D0%A0%D0%BE%D1%81%D1%81%D0%B8%D1%8F%25 ya.ru/%D0%A0%D0%BE%D1%81%D1%81%D0%B8%D1%8F%25]],
  ["should preserve badly escaped url", %w[https://ya.ru/%25D1%2581%25D0%25B8%25D1%258F https://ya.ru], %w[https://ya.ru/%25D1%2581%25D0%25B8%25D1%258F ya.ru/%25D1%2581%25D0%25B8%25D1%258F]],
  ["should handle invalid escape", %w[http://www.ratebeer.com/beer/lindemans-p%EAche-lambic-(p%EAcheresse)/345/ https://acko.net/blog/ahoy-vancouver/], %w[http://www.ratebeer.com/beer/lindemans-p%25EAche-lambic-(p%25EAcheresse)/345/ www.ratebeer.com/beer/lindemans-p%25EAche-lambic-(p%25EAcheresse)/345/]],
  ["should ignore invalid uri with two userinfos", %w[http://ex.p.lo.si.v.edhq.g@silvia.woodw.o.r.t.h@www.temposicilia.it/index.php/component/-/index.php?option=com_kide http://yosefk.com/blog/a-better-future-animated-post.html], nil]
]

RSpec.describe "to_canonical_link" do
  logger = MyLogger.new($stdout)
  test_data.each do |test_case|
    it test_case[0] do
      if test_case[2]
        expected_uri = URI(test_case[2][0])
        expected_result = { canonical_url: test_case[2][1], host: expected_uri.host, uri: expected_uri, url: test_case[2][0] }
      else
        expected_result = nil
      end

      expect(to_canonical_link(test_case[1][0], logger, URI(test_case[1][1])))
        .to eq expected_result
    end
  end
end