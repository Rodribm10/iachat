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

  getMediaSummary({ since, until } = {}) {
    return axios.get(`${this.url}/media_summary`, {
      params: { since, until, timezone_offset: getTimeOffset() },
    });
  }

  getMediaTimeseries(granularity, { since, until } = {}) {
    return axios.get(`${this.url}/media_timeseries`, {
      params: { granularity, since, until, timezone_offset: getTimeOffset() },
    });
  }

  getMediaBreakdown(scope, { since, until } = {}) {
    return axios.get(`${this.url}/media_breakdown`, {
      params: { scope, since, until, timezone_offset: getTimeOffset() },
    });
  }

  getMediaMessages({ type, direction, since, until } = {}) {
    return axios.get(`${this.url}/media_messages`, {
      params: {
        type,
        direction,
        since,
        until,
        timezone_offset: getTimeOffset(),
      },
    });
  }
}

export default new SinalReportsAPI();
