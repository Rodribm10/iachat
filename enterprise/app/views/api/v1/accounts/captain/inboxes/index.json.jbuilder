json.payload do
  json.array! @captain_inboxes do |captain_inbox|
    json.partial! 'api/v1/models/inbox', formats: [:json], resource: captain_inbox.inbox
    json.captain_unit_id captain_inbox.captain_unit_id
    json.captain_unit_name captain_inbox.captain_unit&.name
  end
end

json.meta do
  json.total_count @captain_inboxes.count
  json.page 1
end
