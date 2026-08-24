/* global axios */
import ApiClient from './ApiClient';

const getTimeOffset = () => -new Date().getTimezoneOffset() / 60;

class SinalReportsAPI extends ApiClient {
  constructor() {
    super('sinal_reports', { accountScoped: true, apiVersion: 'v2' });
  }

  getOverview({ since, until, inboxId } = {}) {
    return axios.get(`${this.url}/overview`, {
      params: {
        since,
        until,
        inbox_id: inboxId,
        timezone_offset: getTimeOffset(),
      },
    });
  }

  getOperations({ since, until, inboxId } = {}) {
    return axios.get(`${this.url}/operations`, {
      params: {
        since,
        until,
        inbox_id: inboxId,
        timezone_offset: getTimeOffset(),
      },
    });
  }

  getPrivado({ since, until, inboxId } = {}) {
    return axios.get(`${this.url}/privado`, {
      params: {
        since,
        until,
        inbox_id: inboxId,
        timezone_offset: getTimeOffset(),
      },
    });
  }

  getMediaSummary() {
    return axios.get(`${this.url}/media_summary`, {
      params: { timezone_offset: getTimeOffset() },
    });
  }

  getMediaTimeseries(granularity) {
    return axios.get(`${this.url}/media_timeseries`, {
      params: { granularity, timezone_offset: getTimeOffset() },
    });
  }

  getMediaBreakdown(scope) {
    return axios.get(`${this.url}/media_breakdown`, {
      params: { scope, timezone_offset: getTimeOffset() },
    });
  }

  getMediaMessages({ type, direction } = {}) {
    return axios.get(`${this.url}/media_messages`, {
      params: { type, direction, timezone_offset: getTimeOffset() },
    });
  }
}

export default new SinalReportsAPI();
