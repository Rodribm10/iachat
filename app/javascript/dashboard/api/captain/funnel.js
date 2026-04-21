/* global axios */
import ApiClient from '../ApiClient';

class CaptainFunnel extends ApiClient {
  constructor() {
    super('captain/reports/funnel', { accountScoped: true });
  }

  get(periodDays = 30) {
    return axios.get(this.url, { params: { period_days: periodDays } });
  }
}

export default new CaptainFunnel();
