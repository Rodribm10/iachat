/* global axios */
import ApiClient from '../ApiClient';

class CaptainLifecycleConfig extends ApiClient {
  constructor() {
    super('captain/lifecycle_config', { accountScoped: true });
  }

  show() {
    return axios.get(this.url);
  }

  update(data) {
    return axios.patch(this.url, { config: data });
  }
}

export default new CaptainLifecycleConfig();
