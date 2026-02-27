/* global axios */
import ApiClient from '../ApiClient';

class CaptainReportsAPI extends ApiClient {
  constructor() {
    super('captain/reports', { accountScoped: true });
  }

  getOperational(params = {}) {
    return axios.get(`${this.url}/operational`, { params });
  }

  getInsights(params = {}) {
    return axios.get(`${this.url}/insights`, { params });
  }

  getInsight(id) {
    return axios.get(`${this.url}/insights/${id}`);
  }

  generateInsight(data) {
    return axios.post(`${this.url}/insights/generate`, data);
  }
}

export default new CaptainReportsAPI();
