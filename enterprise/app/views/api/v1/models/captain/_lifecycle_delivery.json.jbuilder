json.id resource.id
json.account_id resource.account_id
json.lifecycle_rule_id resource.lifecycle_rule_id
json.lifecycle_rule_name resource.lifecycle_rule&.name
json.captain_reservation_id resource.captain_reservation_id
json.conversation_id resource.conversation_id
json.inbox_id resource.inbox_id
json.fire_at resource.fire_at&.iso8601
json.sent_at resource.sent_at&.iso8601
json.status resource.status
json.skip_reason resource.skip_reason
json.failure_reason resource.failure_reason
json.rendered_body resource.rendered_body
json.origin resource.origin

if resource.captain_reservation
  json.reservation do
    json.id resource.captain_reservation.id
    json.suite_identifier resource.captain_reservation.suite_identifier
    contact = resource.captain_reservation.contact
    json.customer_name contact&.name
    json.customer_phone contact&.phone_number
  end
end
