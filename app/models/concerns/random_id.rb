module RandomId
  extend ActiveSupport::Concern

  included do
    before_create :generate_random_id
  end

  def RandomId::generate_random_bigint
    SecureRandom.random_bytes(8).unpack("q").first & ((1 << 63) - 1)
  end

  private

  def generate_random_id
    new_id = RandomId::generate_random_bigint
    while self.class.exists?(new_id)
      new_id = RandomId::generate_random_bigint
    end

    # Race condition may happen if two instances generate the same id at the same time, which is highly
    # unlikely
    self.id = new_id
  end
end
