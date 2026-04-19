class Api::V1::Accounts::Contacts::MemoriesController < Api::V1::Accounts::BaseController
  before_action :set_contact
  before_action :set_memory, only: %i[update destroy]

  def index
    @memories = Captain::ContactMemory.active.for_contact(@contact.id).order(created_at: :desc)
    authorize(@memories.first || Captain::ContactMemory.new(account: @contact.account)) if @memories.any?
    render json: { data: @memories.as_json(except: :embedding) }
  end

  def update
    authorize(@memory)
    @memory.update!(memory_params)
    Captain::ContactMemories::UpdateEmbeddingJob.perform_later(@memory.id) if @memory.saved_change_to_content?
    render json: @memory.as_json(except: :embedding)
  end

  def destroy
    authorize(@memory)
    @memory.soft_delete!
    head :no_content
  end

  def bulk_destroy
    authorize(Captain::ContactMemory.new(account: @contact.account))
    # rubocop:disable Rails/SkipsModelValidations
    Captain::ContactMemory.active.for_contact(@contact.id).update_all(deleted_at: Time.current, updated_at: Time.current)
    # rubocop:enable Rails/SkipsModelValidations
    head :no_content
  end

  private

  def set_contact
    @contact = Current.account.contacts.find(params[:contact_id])
  end

  def set_memory
    @memory = Captain::ContactMemory.for_contact(@contact.id).find(params[:id])
  end

  def memory_params
    params.permit(:content, :memory_type, :scope)
  end
end
