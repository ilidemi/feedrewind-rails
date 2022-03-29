class StartFeed < ApplicationRecord
  include RandomId

  belongs_to :start_page, optional: true
end
