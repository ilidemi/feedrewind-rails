class Schedule < ApplicationRecord
  belongs_to :blog
  validates :day_of_week, inclusion: { in: %w(mon tue wed thu fri sat sun) }, presence: true
end
