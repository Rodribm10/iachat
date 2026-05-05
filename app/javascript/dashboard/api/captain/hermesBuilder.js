/* global axios */
import ApiClient from '../ApiClient';

class HermesBuilder extends ApiClient {
  constructor() {
    super('captain/hermes_builder', { accountScoped: true });
  }

  fetchMessages() {
    return axios.get(this.url);
  }

  sendMessage(text) {
    return axios.post(this.url, { text });
  }

  start() {
    return axios.post(`${this.url}/start`);
  }

  reset() {
    return axios.delete(`${this.url}/reset`);
  }

  fetchAssistants() {
    return axios.get(`${this.url}/assistants`);
  }

  validate(slug) {
    return axios.get(`${this.url}/validate`, { params: { slug } });
  }

  repair(slug, repairId) {
    return axios.post(`${this.url}/repair`, { slug, repair_id: repairId });
  }
}

export default new HermesBuilder();
