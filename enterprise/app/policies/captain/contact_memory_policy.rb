class Captain::ContactMemoryPolicy < ApplicationPolicy
  def index?
    @account_user.present?
  end

  def update?
    @account_user&.administrator?
  end

  def destroy?
    @account_user&.administrator?
  end

  def bulk_destroy?
    @account_user&.administrator?
  end
end
