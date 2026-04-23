import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

const ALERT_AUDIO_PATH = '/audio/dashboard/bell.mp3';
const VIBRATION_PATTERN = [500, 200, 500, 200, 500];
const TITLE_FLASH_INTERVAL_MS = 1000;
const NOTIFICATION_TAG = 'chatwoot-aggressive-alert';

// Níveis de severidade — ordem numérica cresce com a urgência.
export const LEVEL = {
  YELLOW: 'yellow',
  ORANGE: 'orange',
  RED: 'red',
};

const LEVEL_SEVERITY = {
  [LEVEL.YELLOW]: 1,
  [LEVEL.ORANGE]: 2,
  [LEVEL.RED]: 3,
};

const showOSNotification = (title, body) => {
  if (typeof window === 'undefined' || !('Notification' in window)) return;
  if (Notification.permission !== 'granted') return;
  try {
    // eslint-disable-next-line no-new
    new Notification(title, {
      body,
      tag: NOTIFICATION_TAG,
      requireInteraction: true,
      renotify: true,
    });
  } catch (e) {
    // Safari iOS lança TypeError no construtor; banner visual + som cobrem.
  }
};

const vibrateDevice = () => {
  if (
    typeof navigator !== 'undefined' &&
    typeof navigator.vibrate === 'function'
  ) {
    navigator.vibrate(VIBRATION_PATTERN);
  }
};

class AggressiveAlertManager {
  constructor() {
    this.audio = null;
    this.titleInterval = null;
    this.originalTitle = typeof document !== 'undefined' ? document.title : '';
    // Map<conversationId, { level, kind, contactName, inboxName, minutes, triggeredAt, temporarilyHidden }>
    this.activeConversations = new Map();
  }

  ensureAudio() {
    if (this.audio) return;
    this.audio = new Audio(ALERT_AUDIO_PATH);
  }

  // Som em loop infinito (usado pro nível RED — urgência máxima)
  playLoopSound() {
    this.ensureAudio();
    this.audio.loop = true;
    const playPromise = this.audio.play();
    if (playPromise && typeof playPromise.catch === 'function') {
      playPromise.catch(() => {
        // Autoplay bloqueado pelo browser — banner visual permanece.
      });
    }
  }

  // Som 1x (usado pro ORANGE — chama atenção mas não satura)
  playOnceSound() {
    // Se já está tocando em loop pra outro alerta, não interfere.
    if (this.hasLoopSound()) return;
    this.ensureAudio();
    this.audio.loop = false;
    const playPromise = this.audio.play();
    if (playPromise && typeof playPromise.catch === 'function') {
      playPromise.catch(() => {});
    }
  }

  hasLoopSound() {
    // Loop está ativo se algum alerta no map tem level === RED e não está hidden.
    return Array.from(this.activeConversations.values()).some(
      entry => entry.level === LEVEL.RED && !entry.temporarilyHidden
    );
  }

  stopSound() {
    if (!this.audio) return;
    this.audio.pause();
    this.audio.currentTime = 0;
    this.audio.loop = false;
  }

  // O título pisca se existir pelo menos 1 alerta visível com level ORANGE ou RED.
  shouldFlashTitle() {
    return Array.from(this.activeConversations.values()).some(
      entry =>
        !entry.temporarilyHidden &&
        (entry.level === LEVEL.ORANGE || entry.level === LEVEL.RED)
    );
  }

  countVisibleAlerts() {
    return Array.from(this.activeConversations.values()).filter(
      entry => !entry.temporarilyHidden
    ).length;
  }

  updateTitleTick(toggle) {
    if (!this.shouldFlashTitle()) {
      document.title = this.originalTitle;
      return;
    }
    const count = this.countVisibleAlerts();
    document.title = toggle
      ? `🚨 (${count}) CONVERSA ABERTA`
      : this.originalTitle;
  }

  startTitleFlash() {
    if (this.titleInterval) return;
    if (!this.shouldFlashTitle()) return;
    let toggle = false;
    this.updateTitleTick(true);
    this.titleInterval = setInterval(() => {
      toggle = !toggle;
      this.updateTitleTick(toggle);
    }, TITLE_FLASH_INTERVAL_MS);
  }

  stopTitleFlash() {
    if (this.titleInterval) {
      clearInterval(this.titleInterval);
      this.titleInterval = null;
    }
    document.title = this.originalTitle;
  }

  // Re-avalia som + título após mudanças no map (trigger/dismiss/hide).
  refreshOutputs() {
    const hasLoop = this.hasLoopSound();
    const shouldFlash = this.shouldFlashTitle();

    if (hasLoop) {
      this.playLoopSound();
    } else {
      this.stopSound();
    }

    if (shouldFlash) {
      this.startTitleFlash();
    } else {
      this.stopTitleFlash();
    }
  }

  /**
   * Dispara ou escala um alerta.
   * @param {Object} opts
   * @param {number|string} opts.conversationId
   * @param {string} opts.level - LEVEL.YELLOW | LEVEL.ORANGE | LEVEL.RED
   * @param {string} opts.kind - 'reopened' | 'inactivity'
   * @param {string} [opts.contactName]
   * @param {string} [opts.inboxName]
   * @param {number} [opts.minutes] - só pra inactivity (5/15/28)
   */
  trigger({
    conversationId,
    level = LEVEL.RED,
    kind = 'reopened',
    contactName,
    inboxName,
    minutes,
  }) {
    if (!conversationId) return;
    const existing = this.activeConversations.get(conversationId);

    // Escalada: se já existe e o novo level é MENOS severo, ignora.
    // Se for mais severo, atualiza (ex: yellow → orange, inactivity).
    if (existing) {
      const currentSev = LEVEL_SEVERITY[existing.level] || 0;
      const incomingSev = LEVEL_SEVERITY[level] || 0;
      // Se o alerta tá "escondido temporariamente" e chegou novo, desesconde.
      if (incomingSev >= currentSev || existing.temporarilyHidden) {
        this.activeConversations.set(conversationId, {
          ...existing,
          level: incomingSev > currentSev ? level : existing.level,
          kind: incomingSev > currentSev ? kind : existing.kind,
          minutes: incomingSev > currentSev ? minutes : existing.minutes,
          contactName: contactName || existing.contactName,
          inboxName: inboxName || existing.inboxName,
          temporarilyHidden: false,
          triggeredAt: Date.now(),
        });
      }
    } else {
      this.activeConversations.set(conversationId, {
        level,
        kind,
        contactName: contactName || '—',
        inboxName: inboxName || '',
        minutes: minutes || null,
        triggeredAt: Date.now(),
        temporarilyHidden: false,
      });
    }

    // Som por nível
    if (level === LEVEL.RED) {
      this.playLoopSound();
    } else if (level === LEVEL.ORANGE) {
      this.playOnceSound();
    }
    // YELLOW: sem som

    if (level === LEVEL.ORANGE || level === LEVEL.RED) {
      showOSNotification(
        '🚨 Conversa aguardando resposta',
        `${contactName || 'Cliente'} — ${inboxName || ''}`.trim()
      );
      vibrateDevice();
    }

    this.startTitleFlash();
    this.emitBusEvent(BUS_EVENTS.AGGRESSIVE_ALERT_TRIGGER, conversationId);
  }

  /**
   * × — dismiss temporário. Remove do visual mas mantém no map como "hidden".
   * Volta a aparecer se escalar (receber mais severo) ou receber nova mensagem.
   * Pra limpar de verdade, o agente tem que responder (então o tracker chama
   * dismissForReply).
   */
  hide(conversationId) {
    const entry = this.activeConversations.get(conversationId);
    if (!entry) return;
    this.activeConversations.set(conversationId, {
      ...entry,
      temporarilyHidden: true,
    });
    this.refreshOutputs();
    this.emitBusEvent(BUS_EVENTS.AGGRESSIVE_ALERT_DISMISS, conversationId);
  }

  /**
   * Dismiss definitivo — chamado quando o agente respondeu ou o tracker
   * detectou que o cliente não é mais o último a mandar.
   */
  dismissForReply(conversationId) {
    if (!this.activeConversations.has(conversationId)) return;
    this.activeConversations.delete(conversationId);
    this.refreshOutputs();
    this.emitBusEvent(BUS_EVENTS.AGGRESSIVE_ALERT_DISMISS, conversationId);
  }

  // Mesmo que hide, mas pra API pública (botão × do banner)
  dismiss(conversationId) {
    this.hide(conversationId);
  }

  dismissAll() {
    if (this.activeConversations.size === 0) return;
    this.activeConversations.clear();
    this.stopSound();
    this.stopTitleFlash();
    this.emitBusEvent(BUS_EVENTS.AGGRESSIVE_ALERT_DISMISS, null);
  }

  emitBusEvent(event, conversationId) {
    emitter.emit(event, {
      conversationId,
      total: this.countVisibleAlerts(),
    });
  }

  getActiveConversations() {
    return Array.from(this.activeConversations.entries())
      .filter(([, data]) => !data.temporarilyHidden)
      .map(([id, data]) => ({ id, ...data }));
  }

  // Level mais alto entre os alertas visíveis — o banner usa pra cor do wrapper.
  getMaxLevel() {
    const visible = Array.from(this.activeConversations.values()).filter(
      entry => !entry.temporarilyHidden
    );
    if (visible.length === 0) return null;
    return visible.reduce((winner, entry) => {
      const sevWinner = LEVEL_SEVERITY[winner] || 0;
      const sevEntry = LEVEL_SEVERITY[entry.level] || 0;
      return sevEntry > sevWinner ? entry.level : winner;
    }, null);
  }
}

const aggressiveAlert = new AggressiveAlertManager();

export default aggressiveAlert;
