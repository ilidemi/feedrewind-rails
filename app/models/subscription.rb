class Subscription < ApplicationRecord
  include RandomId

  default_scope { where(discarded_at: nil) }
  scope :discarded, -> { unscoped.where.not(discarded_at: nil) }
  scope :with_discarded, -> { unscoped }

  belongs_to :user, optional: true
  belongs_to :blog
  has_many :subscription_posts, dependent: :destroy
  has_many :schedules, dependent: :destroy
  has_one :current_rss, dependent: :destroy

  def discarded?
    self.discarded_at.present?
  end

  def discard!
    return false if discarded?
    update_attribute(:discarded_at, Time.current)
  end

  def destroy
    raise "Soft delete is enabled. Use .discard or .destroy_discarded"
  end

  def destroy!
    raise "Soft delete is enabled. Use .discard! or .destroy_discarded!"
  end

  def destroy_discarded
    return false unless discarded?

    method(:destroy).super_method.call
  end

  def destroy_discarded!
    raise ActiveRecord::RecordNotDestroyed.new unless discarded?

    method(:destroy).super_method.call
  end
end
