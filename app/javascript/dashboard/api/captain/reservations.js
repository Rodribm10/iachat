/* global axios */
import ApiClient from '../ApiClient';

class CaptainReservations extends ApiClient {
  constructor() {
    super('captain/reservations', { accountScoped: true });
  }

  get(params = {}) {
    return axios.get(this.url, { params });
  }

  create(data) {
    return axios.post(this.url, { reservation: data });
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }

  revenue(params = {}) {
    return axios.get(`${this.url}/revenue`, { params });
  }

  pix(id) {
    return axios.get(`${this.url}/${id}/pix`);
  }

  cancel(id, reason = '') {
    return axios.post(`${this.url}/${id}/cancel`, { reason });
  }

  markAsPaid(id, note = '') {
    return axios.post(`${this.url}/${id}/mark_as_paid`, { note });
  }

  regeneratePix(id) {
    return axios.post(`${this.url}/${id}/regenerate_pix`, {});
  }
}

export default new CaptainReservations();
