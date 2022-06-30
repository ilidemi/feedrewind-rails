class ApplicationMailer < ActionMailer::Base
  default from: email_address_with_name("feedrewind@feedrewind.com", "FeedRewind")
end
