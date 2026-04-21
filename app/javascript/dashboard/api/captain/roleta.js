/* global axios */
import ApiClient from '../ApiClient';

class CaptainRoleta extends ApiClient {
  constructor() {
    super('captain/roleta', { accountScoped: true });
  }

  pending(params = {}) {
    return axios.get(`${this.url}/pending`, { params });
  }

  redeem(code, notes = '') {
    return axios.post(`${this.url}/redeem`, { code, notes });
  }

  weeklyReport(periodDays = 7) {
    return axios.get(`${this.url}/weekly_report`, {
      params: { period_days: periodDays },
    });
  }
}

export default new CaptainRoleta();
