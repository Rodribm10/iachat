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

  getExecutive(params = {}) {
    return axios.get(`${this.url}/executive`, { params });
  }

  drilldown(params = {}) {
    return axios.get(`${this.url}/executive/drilldown`, { params });
  }

  deliverExecutive(params = {}) {
    return axios.post(`${this.url}/executive/deliver`, params);
  }

  getRetention(params = {}) {
    return axios.get(`${this.url}/retention`, { params });
  }

  getRetentionCohort(params = {}) {
    return axios.get(`${this.url}/retention/cohort`, { params });
  }
}

export default new CaptainReportsAPI();
