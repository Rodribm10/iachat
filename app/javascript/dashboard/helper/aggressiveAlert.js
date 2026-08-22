import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

const ALERT_AUDIO_PATH = '/audio/dashboard/bell.mp3';
// Formata a espera para exibição: "12 min", "2h", "4h30", "3d".
// Fica aqui (e não no componente) para poder ser testada isoladamente — foi
// justamente o cálculo do tempo que estava errado: o banner mostrava o valor
// do limiar (5/15/28) em vez da espera real, então uma conversa de 6 horas
// aparecia como "28 min".
export const formatWaited = (ms, { nowLabel = 'agora' } = {}) => {
  const totalMin = Math.floor(Math.max(0, Number(ms) || 0) / 60000);
  if (!totalMin) return nowLabel;
  if (totalMin < 60) return `${totalMin} min`;

  const hours = Math.floor(totalMin / 60);
  if (hours < 24) {
    const rest = totalMin % 60;
    return rest ? `${hours}h${String(rest).padStart(2, '0')}` : `${hours}h`;
  }
  return `${Math.floor(hours / 24)}d`;
};

const VIBRATION_PATTERN = [500, 200, 500, 200, 500];

// Intervalo entre toques enquanto houver alerta vermelho. Antes o som ficava
// em loop contínuo; espaçar mantém a insistência sem virar tortura.
const RED_CHIME_INTERVAL_MS = 5 * 60 * 1000;
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
    this.redChimeTimer = null;
    this.titleInterval = null;
    this.originalTitle = typeof document !== 'undefined' ? document.title : '';
    // Map<conversationId, { level, kind, contactName, inboxName, minutes, triggeredAt, temporarilyHidden }>
    this.activeConversations = new Map();
  }

  ensureAudio() {
    if (this.audio) return;
    this.audio = new Audio(ALERT_AUDIO_PATH);
  }

  // O som existe pra chamar quem NÃO está olhando. Se a aba está em foco, o
  // visual já resolve — e sino tocando por cima de quem já está trabalhando é
  // o caminho mais curto pra pessoa mutar a aba e perder o alerta pra sempre.
  // eslint-disable-next-line class-methods-use-this
  tabIsFocused() {
    if (typeof document === 'undefined') return false;
    if (document.visibilityState && document.visibilityState !== 'visible') {
      return false;
    }
    return typeof document.hasFocus === 'function' ? document.hasFocus() : true;
  }

  // Um toque, nunca em loop. Ignorado com a aba em foco.
  playChime() {
    if (this.tabIsFocused()) return;
    this.ensureAudio();
    this.audio.loop = false;
    try {
      this.audio.currentTime = 0;
    } catch (e) {
      // alguns browsers recusam seek antes do primeiro play
    }
    const playPromise = this.audio.play();
    if (playPromise && typeof playPromise.catch === 'function') {
      playPromise.catch(() => {
        // Autoplay bloqueado pelo browser — o aviso visual permanece.
      });
    }
  }

  // Enquanto houver alerta vermelho visível, repete o toque a cada
  // RED_CHIME_INTERVAL_MS — mas só com a aba fora de foco. Antes disso era
  // `audio.loop = true`, som contínuo mesmo com a pessoa olhando a tela.
  startRedChimeCycle() {
    if (this.redChimeTimer) return;
    this.playChime();
    this.redChimeTimer = setInterval(() => {
      if (!this.hasRedAlert()) {
        this.stopRedChimeCycle();
        return;
      }
      this.playChime();
    }, RED_CHIME_INTERVAL_MS);
  }

  stopRedChimeCycle() {
    if (!this.redChimeTimer) return;
    clearInterval(this.redChimeTimer);
    this.redChimeTimer = null;
  }

  hasRedAlert() {
    // Existe alerta vermelho visível?
    return Array.from(this.activeConversations.values()).some(
      entry => entry.level === LEVEL.RED && !entry.temporarilyHidden
    );
  }

  stopSound() {
    this.stopRedChimeCycle();
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
    const shouldFlash = this.shouldFlashTitle();

    if (this.hasRedAlert()) {
      this.startRedChimeCycle();
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
   * @param {number} [opts.lastClientAt] - timestamp (ms) da última mensagem do
   *   cliente. Guardamos o instante, não a duração: o tempo de espera é
   *   calculado na hora de exibir, então continua correndo.
   */
  trigger({
    conversationId,
    level = LEVEL.RED,
    kind = 'reopened',
    contactName,
    inboxName,
    lastClientAt,
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
          lastClientAt: lastClientAt || existing.lastClientAt,
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
        lastClientAt: lastClientAt || null,
        triggeredAt: Date.now(),
        temporarilyHidden: false,
      });
    }

    // Som por nível — sempre um toque, nunca contínuo, e só com a aba fora
    // de foco (ver tabIsFocused).
    if (level === LEVEL.RED) {
      this.startRedChimeCycle();
    } else if (level === LEVEL.ORANGE) {
      this.playChime();
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
