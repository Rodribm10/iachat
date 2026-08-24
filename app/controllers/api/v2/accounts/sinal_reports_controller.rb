# Endpoints das páginas "Sinal nativo" (réplicas das telas do app Sinal,
# alimentadas pelos dados da própria conta). Ver docs/specs/relatorios-sinal/.
class Api::V2::Accounts::SinalReportsController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def overview
    render json: V2::Reports::Sinal::OverviewBuilder.new(Current.account, period_params).build
  end

  def operations
    render json: V2::Reports::Sinal::OperationsBuilder.new(Current.account, period_params).build
  end

  def privado
    render json: V2::Reports::Sinal::PrivadoBuilder.new(Current.account, period_params).build
  end

  def media_summary
    render json: media_builder.summary
  end

  def media_timeseries
    render json: { buckets: media_builder.timeseries }
  end

  def media_breakdown
    render json: { rows: media_builder.breakdown }
  end

  def media_messages
    render json: { messages: media_builder.messages }
  end

  private

  def check_authorization
    authorize :report, :view?
  end

  def media_builder
    V2::Reports::Sinal::MediaBuilder.new(
      Current.account,
      params.permit(:granularity, :scope, :type, :direction, :inbox_id, :timezone_offset).to_h.symbolize_keys
    )
  end

  def period_params
    params.permit(:since, :until, :inbox_id, :timezone_offset).to_h.symbolize_keys
  end
end
