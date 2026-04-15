json.payload do
  json.array! @deliveries do |delivery|
    json.partial! 'api/v1/models/captain/lifecycle_delivery', resource: delivery
  end
end

json.meta do
  json.total_count @total_count
  json.page @page
  json.per_page @per_page
end
