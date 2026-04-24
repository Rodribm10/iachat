import AuthAPI from '../api/auth';
import BaseActionCableConnector from '../../shared/helpers/BaseActionCableConnector';
import DashboardAudioNotificationHelper from './AudioAlerts/DashboardAudioNotificationHelper';
import aggressiveAlert from './aggressiveAlert';
import inactivityAlertTracker from './inactivityAlertTracker';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { emitter } from 'shared/helpers/mitt';
import { useImpersonation } from 'dashboard/composables/useImpersonation';

const { isImpersonating } = useImpersonation();

class ActionCableConnector extends BaseActionCableConnector {
  constructor(app, pubsubToken) {
    const { websocketURL = '' } = window.chatwootConfig || {};
    super(app, pubsubToken, websocketURL);
    this.CancelTyping = [];
    this.events = {
      'message.created': this.onMessageCreated,
      'message.updated': this.onMessageUpdated,
      'conversation.created': this.onConversationCreated,
      'conversation.status_changed': this.onStatusChange,
      'user:logout': this.onLogout,
      'page:reload': this.onReload,
      'assignee.changed': this.onAssigneeChanged,
      'conversation.typing_on': this.onTypingOn,
      'conversation.typing_off': this.onTypingOff,
      'conversation.contact_changed': this.onConversationContactChange,
      'presence.update': this.onPresenceUpdate,
      'contact.deleted': this.onContactDelete,
      'contact.updated': this.onContactUpdate,
      'conversation.mentioned': this.onConversationMentioned,
      'notification.created': this.onNotificationCreated,
      'notification.deleted': this.onNotificationDeleted,
      'notification.updated': this.onNotificationUpdated,
      'conversation.read': this.onConversationRead,
      'conversation.updated': this.onConversationUpdated,
      'account.cache_invalidated': this.onCacheInvalidate,
      'copilot.message.created': this.onCopilotMessageCreated,
      'scheduled_message.created': this.onScheduledMessageCreated,
      'scheduled_message.updated': this.onScheduledMessageUpdated,
      'scheduled_message.deleted': this.onScheduledMessageDeleted,
    };
  }

  // eslint-disable-next-line class-methods-use-this
  onReconnect = () => {
    emitter.emit(BUS_EVENTS.WEBSOCKET_RECONNECT);
  };

  // eslint-disable-next-line class-methods-use-this
  onDisconnected = () => {
    emitter.emit(BUS_EVENTS.WEBSOCKET_DISCONNECT);
  };

  isAValidEvent = data => {
    return this.app.$store.getters.getCurrentAccountId === data.account_id;
  };

  onMessageUpdated = data => {
    this.app.$store.dispatch('updateMessage', data);
  };

  onPresenceUpdate = data => {
    if (isImpersonating.value) return;
    this.app.$store.dispatch('contacts/updatePresence', data.contacts);
    this.app.$store.dispatch('agents/updatePresence', data.users);
    this.app.$store.dispatch('setCurrentUserAvailability', data.users);
  };

  onConversationContactChange = payload => {
    const { meta = {}, id: conversationId } = payload;
    const { sender } = meta || {};
    if (conversationId) {
      this.app.$store.dispatch('updateConversationContact', {
        conversationId,
        ...sender,
      });
    }
  };

  onAssigneeChanged = payload => {
    const { id } = payload;
    if (id) {
      this.app.$store.dispatch('updateConversation', payload);
    }
    this.fetchConversationStats();
  };

  onConversationCreated = data => {
    this.app.$store.dispatch('addConversation', data);
    this.fetchConversationStats();
  };

  onConversationRead = data => {
    this.app.$store.dispatch('updateConversation', data);
  };

  // eslint-disable-next-line class-methods-use-this
  onLogout = () => AuthAPI.logout();

  onMessageCreated = data => {
    const {
      conversation: { last_activity_at: lastActivityAt },
      conversation_id: conversationId,
    } = data;
    DashboardAudioNotificationHelper.onNewMessage(data);
    this.app.$store.dispatch('addMessage', data);
    this.app.$store.dispatch('updateConversationLastActivity', {
      lastActivityAt,
      conversationId,
    });
    this.feedInactivityTracker(data);
  };

  // Alimenta o tracker de inatividade:
  // - Cliente (Contact) mandou mensagem em conversa open → começa a contar
  // - Agente (User/AgentBot/Captain) mandou mensagem → limpa (agente respondeu)
  // - Status deixou de ser open → trata como "resolvido", limpa
  feedInactivityTracker = data => {
    if (!this.isAggressiveAlertEnabled()) return;
    const {
      conversation_id: conversationId,
      message_type: messageType,
      sender_type: senderType,
      conversation,
    } = data;

    // message_type: 0=incoming, 1=outgoing, 2=activity, 3=template
    // Activity = evento do sistema (status mudou, etc). Ignora.
    if (messageType === 2 || messageType === 'activity') return;

    // Incoming (cliente) e conversa aberta → começa/renova tracker
    const isIncoming = messageType === 0 || messageType === 'incoming';
    const conversationStatus = conversation && conversation.status;
    if (isIncoming && conversationStatus === 'open') {
      const inboxId = conversation && conversation.inbox_id;
      if (!this.isInboxAllowedForUser(inboxId)) return;
      const contactName =
        conversation && conversation.meta && conversation.meta.sender
          ? conversation.meta.sender.name
          : '';
      const inbox = this.app.$store.getters['inboxes/getInbox']
        ? this.app.$store.getters['inboxes/getInbox'](inboxId)
        : null;
      const inboxName = inbox && inbox.name ? inbox.name : '';
      inactivityAlertTracker.onClientMessage({
        conversationId,
        contactName,
        inboxName,
      });
      return;
    }

    // Qualquer mensagem do agente/bot → limpa tracker
    if (senderType === 'User' || senderType === 'AgentBot') {
      inactivityAlertTracker.onAgentReplyOrResolved(conversationId);
    }
  };

  // Lê account.settings.aggressive_alert_enabled + user.ui_settings
  isAggressiveAlertEnabled = () => {
    const store = this.app.$store;
    const account = store.getters.getCurrentAccount;
    const user = store.getters.getCurrentUser;

    // Default true se settings não vieram ainda (não bloqueia no boot).
    const accountEnabled =
      !account ||
      !account.settings ||
      account.settings.aggressive_alert_enabled !== false;
    const userEnabled =
      !user ||
      !user.ui_settings ||
      user.ui_settings.aggressive_alert_enabled !== false;

    return accountEnabled && userEnabled;
  };

  // Filtra alertas por inbox conforme a preferência do user.
  // ui_settings.aggressive_alert_inbox_ids:
  //   - null/undefined → todas as inboxes (default, legado)
  //   - [] (vazio) → nenhuma inbox (silenciou tudo)
  //   - [1, 2, 3] → só essas inboxes
  isInboxAllowedForUser = inboxId => {
    if (inboxId == null) return true;
    const user = this.app.$store.getters.getCurrentUser;
    const allowed =
      user && user.ui_settings && user.ui_settings.aggressive_alert_inbox_ids;
    if (allowed == null) return true;
    if (!Array.isArray(allowed)) return true;
    // Inbox ids podem vir como number no evento e string no ui_settings.
    return allowed.some(id => Number(id) === Number(inboxId));
  };

  // eslint-disable-next-line class-methods-use-this
  onReload = () => window.location.reload();

  onStatusChange = data => {
    this.maybeTriggerAggressiveAlert(data);
    // Se saiu de 'open' (resolvida/snoozada/pending), limpa qualquer alerta
    // pendente pra essa conversa.
    if (data && data.id && data.status && data.status !== 'open') {
      inactivityAlertTracker.onAgentReplyOrResolved(data.id);
    }
    this.app.$store.dispatch('updateConversation', data);
    this.fetchConversationStats();
  };

  // Dispara banner RED toda vez que a conversa transita pra 'open'.
  // Broadcast `conversation.status_changed` só chega em mudança real,
  // então confiar no evento é suficiente.
  maybeTriggerAggressiveAlert = data => {
    if (!data || data.status !== 'open') return;
    if (!this.isAggressiveAlertEnabled()) return;
    if (!this.isInboxAllowedForUser(data.inbox_id)) return;
    const store = this.app.$store;
    const contactName =
      data.meta && data.meta.sender ? data.meta.sender.name : '';
    const inbox = store.getters['inboxes/getInbox']
      ? store.getters['inboxes/getInbox'](data.inbox_id)
      : null;
    const inboxName = inbox && inbox.name ? inbox.name : '';

    aggressiveAlert.trigger({
      conversationId: data.id,
      level: 'red',
      kind: 'reopened',
      contactName,
      inboxName,
    });
  };

  onConversationUpdated = data => {
    this.app.$store.dispatch('updateConversation', data);
    this.fetchConversationStats();
  };

  onScheduledMessageCreated = data => {
    this.app.$store.dispatch('handleScheduledMessageCreated', data);
  };

  onScheduledMessageUpdated = data => {
    this.app.$store.dispatch('handleScheduledMessageUpdated', data);
  };

  onScheduledMessageDeleted = data => {
    this.app.$store.dispatch('handleScheduledMessageDeleted', data);
  };

  onTypingOn = ({ conversation, user }) => {
    const conversationId = conversation.id;

    this.clearTimer(conversationId);
    this.app.$store.dispatch('conversationTypingStatus/create', {
      conversationId,
      user,
    });
    this.initTimer({ conversation, user });
  };

  onTypingOff = ({ conversation, user }) => {
    const conversationId = conversation.id;

    this.clearTimer(conversationId);
    this.app.$store.dispatch('conversationTypingStatus/destroy', {
      conversationId,
      user,
    });
  };

  onConversationMentioned = data => {
    this.app.$store.dispatch('addMentions', data);
  };

  clearTimer = conversationId => {
    const timerEvent = this.CancelTyping[conversationId];

    if (timerEvent) {
      clearTimeout(timerEvent);
      this.CancelTyping[conversationId] = null;
    }
  };

  initTimer = ({ conversation, user }) => {
    const conversationId = conversation.id;
    // Turn off typing automatically after 30 seconds
    this.CancelTyping[conversationId] = setTimeout(() => {
      this.onTypingOff({ conversation, user });
    }, 30000);
  };

  // eslint-disable-next-line class-methods-use-this
  fetchConversationStats = () => {
    emitter.emit('fetch_conversation_stats');
  };

  onContactDelete = data => {
    this.app.$store.dispatch(
      'contacts/deleteContactThroughConversations',
      data.id
    );
    this.fetchConversationStats();
  };

  onContactUpdate = data => {
    this.app.$store.dispatch('contacts/updateContact', data);
  };

  onNotificationCreated = data => {
    this.app.$store.dispatch('notifications/addNotification', data);
  };

  onNotificationDeleted = data => {
    this.app.$store.dispatch('notifications/deleteNotification', data);
  };

  onNotificationUpdated = data => {
    this.app.$store.dispatch('notifications/updateNotification', data);
  };

  onCopilotMessageCreated = data => {
    this.app.$store.dispatch('copilotMessages/upsert', data);
  };

  onCacheInvalidate = data => {
    const keys = data.cache_keys;
    this.app.$store.dispatch('labels/revalidate', { newKey: keys.label });
    this.app.$store.dispatch('inboxes/revalidate', { newKey: keys.inbox });
    this.app.$store.dispatch('teams/revalidate', { newKey: keys.team });
  };
}

export default {
  init(store, pubsubToken) {
    return new ActionCableConnector({ $store: store }, pubsubToken);
  },
};
