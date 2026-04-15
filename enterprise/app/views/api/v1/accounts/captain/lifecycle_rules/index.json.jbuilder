json.payload do
  json.array! @rules do |rule|
    json.partial! 'api/v1/models/captain/lifecycle_rule', resource: rule
  end
end

json.meta do
  json.total_count @rules.count
end
