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
}

export default new CaptainReservations();
