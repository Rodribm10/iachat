/* global axios */
import ApiClient from '../ApiClient';

class CaptainNotificationTemplatesAPI extends ApiClient {
  constructor() {
    super('captain/units', { accountScoped: true });
  }

  getTemplates(unitId) {
    return axios.get(`${this.url}/${unitId}/notification_templates`);
  }

  createTemplate(unitId, data) {
    return axios.post(`${this.url}/${unitId}/notification_templates`, {
      notification_template: data,
    });
  }

  updateTemplate(unitId, id, data) {
    return axios.patch(`${this.url}/${unitId}/notification_templates/${id}`, {
      notification_template: data,
    });
  }

  deleteTemplate(unitId, id) {
    return axios.delete(`${this.url}/${unitId}/notification_templates/${id}`);
  }
}

export default new CaptainNotificationTemplatesAPI();
