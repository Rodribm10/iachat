class Api::V1::Accounts::Captain::GalleryItemsController < Api::V1::Accounts::BaseController
  before_action :set_gallery_item, only: [:show, :update, :destroy]

  # rubocop:disable Metrics/AbcSize
  def index
    items = Current.account.captain_gallery_items
                   .includes(:captain_unit, :inbox, image_attachment: :blob)
                   .ordered

    items = items.where(scope: permitted_params[:scope]) if permitted_params[:scope].present?
    items = items.where(inbox_id: permitted_params[:inbox_id]) if permitted_params[:inbox_id].present?
    items = items.where(captain_unit_id: permitted_params[:captain_unit_id]) if permitted_params[:captain_unit_id].present?
    items = items.where('LOWER(suite_category) = ?', permitted_params[:suite_category].to_s.downcase) if permitted_params[:suite_category].present?
    items = items.where('LOWER(suite_number) = ?', permitted_params[:suite_number].to_s.downcase) if permitted_params[:suite_number].present?

    render json: items.map { |item| serialize_item(item) }
  end
  # rubocop:enable Metrics/AbcSize

  def show
    render json: serialize_item(@gallery_item)
  end

  def create
    @gallery_item = Current.account.captain_gallery_items.build(gallery_item_attributes)
    @gallery_item.created_by = Current.user if Current.user.present?
    attach_image(@gallery_item)
    @gallery_item.save!

    render json: serialize_item(@gallery_item), status: :created
  rescue ActiveRecord::RecordInvalid
    render json: { errors: @gallery_item.errors.full_messages }, status: :unprocessable_entity
  end

  def update
    @gallery_item.assign_attributes(gallery_item_attributes)
    attach_image(@gallery_item)
    @gallery_item.save!

    render json: serialize_item(@gallery_item)
  rescue ActiveRecord::RecordInvalid
    render json: { errors: @gallery_item.errors.full_messages }, status: :unprocessable_entity
  end

  def destroy
    @gallery_item.destroy!
    head :no_content
  end

  private

  def set_gallery_item
    @gallery_item = Current.account.captain_gallery_items.find(permitted_params[:id])
  end

  def permitted_params
    params.permit(:id, :scope, :inbox_id, :captain_unit_id, :suite_category, :suite_number)
  end

  def gallery_item_params
    params.require(:captain_gallery_item).permit(
      :scope,
      :inbox_id,
      :captain_unit_id,
      :suite_category,
      :suite_number,
      :description,
      :active,
      :image
    )
  end

  def gallery_item_attributes
    attrs = gallery_item_params.except(:image)
    normalize_gallery_scope!(attrs)
    attrs
  end

  def attach_image(gallery_item)
    image = gallery_item_params[:image]
    return if image.blank?

    gallery_item.image.attach(image)
  end

  # rubocop:disable Metrics/AbcSize
  def serialize_item(item)
    {
      id: item.id,
      account_id: item.account_id,
      scope: item.scope,
      inbox_id: item.inbox_id,
      inbox_name: item.inbox&.name,
      captain_unit_id: item.captain_unit_id,
      captain_unit_name: item.captain_unit&.name,
      suite_category: item.suite_category,
      suite_number: item.suite_number,
      description: item.description,
      active: item.active,
      image_url: image_url(item),
      image_filename: item.image.attached? ? item.image.filename.to_s : nil,
      image_content_type: item.image.attached? ? item.image.content_type : nil,
      image_byte_size: item.image.attached? ? item.image.byte_size : nil,
      created_at: item.created_at.to_i,
      updated_at: item.updated_at.to_i
    }
  end
  # rubocop:enable Metrics/AbcSize

  def image_url(item)
    return nil unless item.image.attached?

    Rails.application.routes.url_helpers.rails_blob_path(item.image, only_path: true)
  end

  def normalize_gallery_scope!(attrs)
    if attrs[:inbox_id].blank? && attrs[:captain_unit_id].present?
      unit = Current.account.captain_units.find_by(id: attrs[:captain_unit_id])
      attrs[:inbox_id] = unit&.inbox_id
    end

    scope = attrs[:scope].presence
    scope = attrs[:inbox_id].present? ? 'inbox' : 'global' if scope.blank?

    attrs[:scope] = scope
    attrs[:inbox_id] = nil if scope == 'global'
  end
end
