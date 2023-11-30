source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '2.7.4'

gem 'rails', '6.1.4.1'
gem 'pg', '~> 1.1'
gem 'puma', '~> 5.0'
gem 'sass-rails', '>= 6'
gem 'webpacker', '~> 5.0'
gem 'jbuilder', '~> 2.7'

# Reduces boot times through caching; required in config/boot.rb
gem 'bootsnap', '>= 1.4.4', require: false

group :development, :test do
  # Call 'byebug' anywhere in the code to stop execution and get a debugger console
  gem 'byebug', platforms: [:mri, :mingw, :x64_mingw]
end

group :development do
  # Access an interactive console on exception pages or by calling 'console' anywhere in the code.
  gem 'web-console', '>= 4.1.0'
  # Display performance information such as SQL time and flame graphs for each request in your browser.
  # Can be configured to work on production as well see: https://github.com/MiniProfiler/rack-mini-profiler/blob/master/README.md
  gem 'rack-mini-profiler', '~> 2.0'
  gem 'listen', '~> 3.3'
  # Spring speeds up development by keeping your application running in the background. Read more: https://github.com/rails/spring
  gem 'spring'

  gem 'sqlite3', '~> 1.4', '>= 1.4.2'
  gem 'derailed', '~> 0.1', '>= 0.1.0'
end

group :test do
  # Adds support for Capybara system testing and selenium driver
  gem 'capybara', '>= 3.37'
  gem 'selenium-webdriver', '~> 4.4', '= 4.4.0'
  # Easy installation and use of web drivers to run system tests with browsers
  gem 'webdrivers', '~> 5.3', '= 5.3.0'
  gem 'minitest', '~> 5.14'
end

# Include tzinfo-data on all platforms so that upgrades are manual
gem 'tzinfo-data', '1.2022.6'

gem "addressable", "~> 2.2", ">= 2.2.4"
gem "nokogiri", "~> 1.12", ">= 1.12.5"
gem 'ox', '~> 2.0', '>= 2.14.0'
gem 'delayed_job', '~> 4.1', '>= 4.1.9'
gem 'delayed_job_active_record', '~> 4.1', '>= 4.1.5'
gem 'daemons', '~> 1.2', '>= 1.2.3'
gem 'bcrypt', '~> 3.1', '>= 3.1.12'
gem 'rspec', '~> 3.10', '>= 3.10.0'
gem 'rspec-rails', '~> 5.0', '>= 5.0.1'
gem 'gnuplot', '~> 2.6', '>= 2.6.2'
gem 'puppeteer-ruby', '~> 0.45', '>= 0.45.0'
gem 'htmlentities', '~> 4.3', '>= 4.3.4'
gem 'barnes', '~> 0.0.9', '>= 0.0.9'
gem "tailwindcss-rails", "~> 2.0"
gem "postmark-rails", "~> 0.22", ">= 0.22.0"
gem "browser", "~> 5.3", ">= 5.3.1"

# 2.8.0 introduced a dependency on net-imap which depends on net-protocol which overrides constants and spits out warnings
gem "mail", "2.7.1"