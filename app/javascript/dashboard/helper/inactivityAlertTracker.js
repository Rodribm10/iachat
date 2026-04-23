import aggressiveAlert, { LEVEL } from './aggressiveAlert';

// Thresholds de inatividade. Cada um dispara UMA vez por conversa (enquanto
// o cliente segue sendo o último a falar). Ordem: do menos urgente ao mais.
const THRESHOLDS = [
  { minutes: 5, level: LEVEL.YELLOW },
  { minutes: 15, level: LEVEL.ORANGE },
  { minutes: 28, level: LEVEL.RED },
];

// Checa o estado dos alertas a cada 20s — granularidade suficiente pra
// não perder threshold (a menor janela entre thresholds é 5min = 300s).
const CHECK_INTERVAL_MS = 20_000;

class InactivityAlertTracker {
  constructor() {
    // Map<conversationId, { lastClientAt, firedMinutes: Set<number>, contactName, inboxName }>
    this.conversations = new Map();
    this.interval = null;
    this.enabledGetter = () => true; // injetado pelo actionCable com o store
  }

  setEnabledGetter(fn) {
    this.enabledGetter = fn;
  }

  start() {
    if (this.interval) return;
    this.interval = setInterval(() => this.tick(), CHECK_INTERVAL_MS);
  }

  stop() {
    if (!this.interval) return;
    clearInterval(this.interval);
    this.interval = null;
  }

  /**
   * Registra ou atualiza que o CLIENTE mandou mensagem em uma conversa aberta.
   * Zera os thresholds se já existia (porque o relógio recomeça).
   */
  onClientMessage({ conversationId, contactName, inboxName }) {
    if (!conversationId) return;
    this.conversations.set(conversationId, {
      lastClientAt: Date.now(),
      firedMinutes: new Set(),
      contactName: contactName || '—',
      inboxName: inboxName || '',
    });
    this.start();
  }

  /**
   * Limpa a conversa — agente respondeu ou cenário não mais aplicável.
   * Também dá dismiss no banner pra parar som.
   */
  onAgentReplyOrResolved(conversationId) {
    if (!conversationId) return;
    if (this.conversations.has(conversationId)) {
      this.conversations.delete(conversationId);
    }
    aggressiveAlert.dismissForReply(conversationId);
    if (this.conversations.size === 0) this.stop();
  }

  tick() {
    if (!this.enabledGetter()) return;
    if (this.conversations.size === 0) {
      this.stop();
      return;
    }
    const now = Date.now();
    Array.from(this.conversations.entries()).forEach(
      ([conversationId, entry]) => {
        const elapsedMin = (now - entry.lastClientAt) / 60000;
        THRESHOLDS.forEach(t => {
          if (elapsedMin < t.minutes) return;
          if (entry.firedMinutes.has(t.minutes)) return;
          entry.firedMinutes.add(t.minutes);
          aggressiveAlert.trigger({
            conversationId,
            level: t.level,
            kind: 'inactivity',
            contactName: entry.contactName,
            inboxName: entry.inboxName,
            minutes: t.minutes,
          });
        });
      }
    );
  }
}

const inactivityAlertTracker = new InactivityAlertTracker();

export default inactivityAlertTracker;
