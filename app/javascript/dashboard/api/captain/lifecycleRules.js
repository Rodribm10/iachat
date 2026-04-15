/* global axios */
import ApiClient from '../ApiClient';

class CaptainLifecycleRules extends ApiClient {
  constructor() {
    super('captain/lifecycle_rules', { accountScoped: true });
  }

  get(params = {}) {
    return axios.get(this.url, { params });
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }

  create(data) {
    return axios.post(this.url, { rule: data });
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, { rule: data });
  }

  delete(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export default new CaptainLifecycleRules();
