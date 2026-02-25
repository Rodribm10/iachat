/* global axios */
import ApiClient from '../ApiClient';

class JasmineAPI extends ApiClient {
  constructor() {
    super('inboxes', { accountScoped: true });
  }

  // Helper to get account-scoped jasmine base URL
  get jasmineUrl() {
    return `${this.apiVersion}/accounts/${this.accountIdFromRoute}/jasmine`;
  }

  // Inbox Settings
  getSettings(inboxId) {
    return axios.get(`${this.url}/${inboxId}/jasmine/config`);
  }

  updateSettings(inboxId, data) {
    return axios.patch(`${this.url}/${inboxId}/jasmine/config`, data);
  }

  // Collections (Account-scoped)
  getCollections(params = {}) {
    return axios.get(`${this.jasmineUrl}/collections`, { params });
  }

  createCollection(data) {
    return axios.post(`${this.jasmineUrl}/collections`, data);
  }

  deleteCollection(collectionId) {
    return axios.delete(`${this.jasmineUrl}/collections/${collectionId}`);
  }

  // Links (Inbox Collections)
  getInboxCollections(inboxId) {
    return axios.get(`${this.url}/${inboxId}/jasmine/collections`);
  }

  linkCollection(inboxId, collectionId, priority = 0) {
    return axios.post(`${this.url}/${inboxId}/jasmine/collections`, {
      collection_id: collectionId,
      priority,
    });
  }

  unlinkCollection(inboxId, collectionId) {
    return axios.delete(
      `${this.url}/${inboxId}/jasmine/collections/${collectionId}`
    );
  }

  // Documents
  getDocuments(collectionId) {
    return axios.get(
      `${this.jasmineUrl}/collections/${collectionId}/documents`
    );
  }

  uploadDocument(collectionId, content, title) {
    return axios.post(
      `${this.jasmineUrl}/collections/${collectionId}/documents`,
      {
        title,
        content,
      }
    );
  }

  deleteDocument(collectionId, documentId) {
    return axios.delete(
      `${this.jasmineUrl}/collections/${collectionId}/documents/${documentId}`
    );
  }

  // Playground
  testPlayground(inboxId, message) {
    return axios.post(`${this.url}/${inboxId}/jasmine/playground`, { message });
  }

  // Tools
  getTools(inboxId) {
    return axios.get(`${this.url}/${inboxId}/jasmine/tools`);
  }

  updateTool(inboxId, toolKey, data) {
    return axios.patch(`${this.url}/${inboxId}/jasmine/tools/${toolKey}`, data);
  }

  testTool(inboxId, toolKey) {
    return axios.post(`${this.url}/${inboxId}/jasmine/tools/${toolKey}/test`);
  }
}

export default new JasmineAPI();
