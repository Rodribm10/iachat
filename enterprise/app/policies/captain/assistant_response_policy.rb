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

    if @account_user.custom_role.present?
      return @account_user.custom_role.permissions.include?('knowledge_base_manage')
    end

    @account_user.agent?
  end
end
