/* global axios */
import ApiClient from '../ApiClient';

class ContactMemoriesAPI extends ApiClient {
  constructor() {
    super('memories', { accountScoped: true });
  }

  get url() {
    return `${this.baseUrl()}/contacts/${this.contactId}/memories`;
  }

  list(contactId) {
    this.contactId = contactId;
    return axios.get(this.url);
  }

  update(contactId, id, payload) {
    this.contactId = contactId;
    return axios.patch(`${this.url}/${id}`, payload);
  }

  destroy(contactId, id) {
    this.contactId = contactId;
    return axios.delete(`${this.url}/${id}`);
  }

  forgetAll(contactId) {
    this.contactId = contactId;
    return axios.delete(this.url);
  }
}

export default new ContactMemoriesAPI();
