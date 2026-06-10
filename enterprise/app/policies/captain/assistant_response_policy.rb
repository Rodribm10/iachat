class Captain::AssistantResponsePolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def show?
    index?
  end

  def create?
    manage?
  end

  def update?
    manage?
  end

  def destroy?
    manage?
  end

  private

  def manage?
    return true if @account_user.administrator?

    @account_user.custom_role&.permissions&.include?('knowledge_base_manage') || false
  end
end
