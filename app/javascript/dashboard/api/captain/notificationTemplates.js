import ApiClient from '../ApiClient';

class NotificationTemplatesAPI extends ApiClient {
  constructor() {
    super('inboxes', { accountScoped: true });
  }

  getAll(inboxId) {
    return this.get(`${inboxId}/notification_templates`);
  }

  create(inboxId, data) {
    return this.post(`${inboxId}/notification_templates`, {
      notification_template: data,
    });
  }

  update(inboxId, id, data) {
    return this.patch(`${inboxId}/notification_templates/${id}`, {
      notification_template: data,
    });
  }

  delete(inboxId, id) {
    return this.delete(`${inboxId}/notification_templates/${id}`);
  }
}

export default new NotificationTemplatesAPI();
