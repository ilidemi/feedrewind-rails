class OldBlog < ApplicationRecord
  default_scope { where(discarded_at: nil) }
  scope :discarded, -> { unscoped.where.not(discarded_at: nil) }
  scope :with_discarded, -> { unscoped }

  before_create :generate_random_id

  belongs_to :user, optional: true
  has_many :post, dependent: :destroy
  validates :name, presence: true
  validates :url, presence: true

  def generate_random_id
    new_id = generate_random_bigint
    while OldBlog.exists?(new_id)
      new_id = generate_random_bigint
    end

    # Race condition may happen if two instances generate the same id at the same time, which is highly
    # unlikely
    self.id = new_id
  end

  def discarded?
    self.discarded_at.present?
  end

  def discard!
    return false if discarded?
    update_attribute(:discarded_at, Time.current)
  end

  def destroy
    raise "Soft delete is enabled. Use .discard! or .destroy_discarded"
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

  private

  def generate_random_bigint
    SecureRandom.random_bytes(8).unpack("q").first & ((1 << 63) - 1)
  end
end
