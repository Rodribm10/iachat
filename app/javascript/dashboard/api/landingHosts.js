// API client para LandingHosts da caixa de entrada
/* global axios */

export default {
  getHosts(accountId, inboxId) {
    return axios.get(
      `/api/v1/accounts/${accountId}/inboxes/${inboxId}/landing_hosts`
    );
  },
  createHost(accountId, inboxId, data) {
    return axios.post(
      `/api/v1/accounts/${accountId}/inboxes/${inboxId}/landing_hosts`,
      { landing_host: data }
    );
  },
  updateHost(accountId, inboxId, id, data) {
    return axios.patch(
      `/api/v1/accounts/${accountId}/inboxes/${inboxId}/landing_hosts/${id}`,
      { landing_host: data }
    );
  },
  deleteHost(accountId, inboxId, id) {
    return axios.delete(
      `/api/v1/accounts/${accountId}/inboxes/${inboxId}/landing_hosts/${id}`
    );
  },
};
