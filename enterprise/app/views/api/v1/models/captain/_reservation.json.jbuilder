marker = Captain::Reservations::MarkerBuilder.build_for(resource)
contact = resource.contact
unit = resource.unit
conversation = resource.conversation

json.id resource.id
json.status resource.status
json.status_label marker['status_label']
json.ui_status marker['status']
json.payment_status resource.payment_status
json.suite_identifier resource.suite_identifier
json.check_in_at resource.check_in_at&.iso8601
json.check_out_at resource.check_out_at&.iso8601
json.updated_at resource.updated_at&.iso8601
json.created_at resource.created_at&.iso8601

json.total_amount resource.total_amount.to_f
json.deposit_amount marker['deposit_amount']&.to_f
json.amount marker['amount']&.to_f
json.amount_kind marker['amount_kind']

json.customer_name contact&.name
json.customer_phone contact&.phone_number
json.customer_cpf contact&.custom_attributes&.dig('cpf')

json.unit_id unit&.id
json.unit_name unit&.name

json.conversation_id conversation&.id || resource.conversation_id
json.conversation_display_id conversation&.display_id

json.pix_copy_paste marker['pix_copy_paste']
json.pix_reason marker['pix_reason']
json.pix_status marker['pix_status']

json.reservation_marker marker
