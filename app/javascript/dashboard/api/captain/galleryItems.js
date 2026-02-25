/* global axios */

import ApiClient from '../../api/ApiClient';

class CaptainGalleryItemsAPI extends ApiClient {
  constructor() {
    super('captain/gallery_items', { accountScoped: true });
  }

  getItems(params = {}) {
    return axios.get(this.url, { params });
  }

  getItem(id) {
    return this.show(id);
  }

  createItem(formData) {
    return axios.post(this.url, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  updateItem(id, formData) {
    return axios.patch(`${this.url}/${id}`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  deleteItem(id) {
    return this.delete(id);
  }
}

export default new CaptainGalleryItemsAPI();
