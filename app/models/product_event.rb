require 'securerandom'

class ProductEvent < ApplicationRecord
  def ProductEvent::from_request!(
    request, product_user_id:, event_type:, event_properties: nil, user_properties: nil
  )
    ProductEvent.create!(
      product_user_id: product_user_id,
      event_type: event_type,
      event_properties: event_properties,
      user_properties: user_properties,
      user_agent: request.user_agent,
      user_ip: request.ip,
    )
  end

  def ProductEvent::dummy_create!(event_type:, event_properties: nil)
    ProductEvent.create!(
      product_user_id: "dummy-#{SecureRandom.uuid}",
      event_type: event_type,
      event_properties: event_properties,
      user_properties: {
        is_dummy: true
      }
    )
  end
end

