class Api::V1::Accounts::Captain::InboxesController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action -> { check_authorization(Captain::Assistant) }

  before_action :set_assistant
  def index
    @captain_inboxes = @assistant.captain_inboxes.includes(:inbox, :captain_unit)
  end

  def create
    inbox = Current.account.inboxes.find(assistant_params[:inbox_id])
    @captain_inbox = CaptainInbox.find_or_initialize_by(inbox_id: inbox.id)

    if @captain_inbox.persisted? && @captain_inbox.captain_assistant_id != @assistant.id
      render json: { error: 'Inbox já está conectada a outro assistente.' }, status: :unprocessable_entity
      return
    end

    @captain_inbox.captain_assistant = @assistant
    @captain_inbox.captain_unit_id = linked_captain_unit_id_for(inbox)
    @captain_inbox.save!
    move_open_conversations_to_pending(inbox)
  end

  def destroy
    @captain_inbox = @assistant.captain_inboxes.find_by!(inbox_id: permitted_params[:inbox_id])
    @captain_inbox.destroy!
    head :no_content
  end

  private

  def set_assistant
    @assistant = account_assistants.find(permitted_params[:assistant_id])
  end

  def account_assistants
    @account_assistants ||= Current.account.captain_assistants
  end

  def permitted_params
    params.permit(:assistant_id, :id, :account_id, :inbox_id)
  end

  def assistant_params
    params.require(:inbox).permit(:inbox_id)
  end

  def move_open_conversations_to_pending(inbox)
    inbox.conversations.open.unassigned
         .where(assignee_agent_bot_id: nil)
         .update_all(status: Conversation.statuses[:pending], updated_at: Time.current)
  end

  def linked_captain_unit_id_for(inbox)
    return nil unless defined?(Captain::Unit)

    Current.account.captain_units.find_by(inbox_id: inbox.id)&.id
  end
end
