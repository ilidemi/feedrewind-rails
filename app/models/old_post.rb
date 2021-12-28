class OldPost < ApplicationRecord
  belongs_to :blog
  validates :link, presence: true, format: { with: /\Ahttps?:\/\/.+\z/,
                                             message: "link has to be a valid url" }
end
