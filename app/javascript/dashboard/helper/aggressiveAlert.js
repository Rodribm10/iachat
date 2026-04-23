import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

const ALERT_AUDIO_PATH = '/audio/dashboard/bell.mp3';
const VIBRATION_PATTERN = [500, 200, 500, 200, 500];
const TITLE_FLASH_INTERVAL_MS = 1000;
const NOTIFICATION_TAG = 'chatwoot-aggressive-alert';

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
    this.activeConversations = new Map();
  }

  ensureAudio() {
    if (this.audio) return;
    this.audio = new Audio(ALERT_AUDIO_PATH);
    this.audio.loop = true;
  }

  playSound() {
    this.ensureAudio();
    const playPromise = this.audio.play();
    if (playPromise && typeof playPromise.catch === 'function') {
      playPromise.catch(() => {
        // Autoplay bloqueado pelo browser — banner visual permanece.
      });
    }
  }

  stopSound() {
    if (!this.audio) return;
    this.audio.pause();
    this.audio.currentTime = 0;
  }

  updateTitleTick(toggle) {
    const count = this.activeConversations.size;
    if (count === 0) {
      document.title = this.originalTitle;
      return;
    }
    document.title = toggle
      ? `🚨 (${count}) CONVERSA ABERTA`
      : this.originalTitle;
  }

  startTitleFlash() {
    if (this.titleInterval) return;
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

  trigger({ conversationId, contactName, inboxName, previousStatus }) {
    if (!conversationId) return;
    if (this.activeConversations.has(conversationId)) return;

    this.activeConversations.set(conversationId, {
      contactName: contactName || '—',
      inboxName: inboxName || '',
      previousStatus: previousStatus || '',
      triggeredAt: Date.now(),
    });

    this.playSound();
    showOSNotification(
      '🚨 Conversa aberta aguardando resposta',
      `${contactName || 'Cliente'} — ${inboxName || ''}`.trim()
    );
    vibrateDevice();
    this.startTitleFlash();

    emitter.emit(BUS_EVENTS.AGGRESSIVE_ALERT_TRIGGER, {
      conversationId,
      contactName,
      inboxName,
      previousStatus,
      total: this.activeConversations.size,
    });
  }

  dismiss(conversationId) {
    if (!this.activeConversations.has(conversationId)) return;
    this.activeConversations.delete(conversationId);

    if (this.activeConversations.size === 0) {
      this.stopSound();
      this.stopTitleFlash();
    } else {
      this.updateTitleTick(true);
    }

    emitter.emit(BUS_EVENTS.AGGRESSIVE_ALERT_DISMISS, {
      conversationId,
      total: this.activeConversations.size,
    });
  }

  dismissAll() {
    if (this.activeConversations.size === 0) return;
    this.activeConversations.clear();
    this.stopSound();
    this.stopTitleFlash();
    emitter.emit(BUS_EVENTS.AGGRESSIVE_ALERT_DISMISS, {
      conversationId: null,
      total: 0,
    });
  }

  getActiveConversations() {
    return Array.from(this.activeConversations.entries()).map(([id, data]) => ({
      id,
      ...data,
    }));
  }
}

const aggressiveAlert = new AggressiveAlertManager();

export default aggressiveAlert;
