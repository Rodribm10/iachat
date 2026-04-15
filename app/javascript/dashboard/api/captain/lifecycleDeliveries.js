/* global axios */
import ApiClient from '../ApiClient';

class CaptainLifecycleDeliveries extends ApiClient {
  constructor() {
    super('captain/lifecycle_deliveries', { accountScoped: true });
  }

  get(params = {}) {
    return axios.get(this.url, { params });
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }
}

export default new CaptainLifecycleDeliveries();
