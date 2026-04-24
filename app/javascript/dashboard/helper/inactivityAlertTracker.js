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

// Logs opt-in. Ativar no DevTools: window.__AGGRESSIVE_DEBUG__ = true
// Serve pra investigar porque o banner de inatividade não dispara numa
// conversa específica sem ter que tornar logs permanentes em prod.
const debug = (...args) => {
  if (
    typeof window !== 'undefined' &&
    // eslint-disable-next-line no-underscore-dangle
    window.__AGGRESSIVE_DEBUG__
  ) {
    // eslint-disable-next-line no-console
    console.info('[aggressive-alert]', ...args);
  }
};

function findLastNonActivityMessage(conv) {
  // 1) Preferir o campo dedicado do payload da listagem — o serializer
  // já filtra atividades (`non_activity_messages`) antes de setar aqui.
  if (conv.last_non_activity_message) return conv.last_non_activity_message;
  // 2) Fallback pro array `messages` (só tem a última mensagem, e pode ser
  // uma activity — filtra pra garantir).
  if (conv.messages && conv.messages.length) {
    const nonActivity = conv.messages.filter(
      m => m && m.message_type !== 2 && m.message_type !== 'activity'
    );
    if (nonActivity.length) return nonActivity[nonActivity.length - 1];
  }
  return null;
}

// Chatwoot usa Unix timestamp (segundos) na maior parte dos endpoints e
// ISO em alguns. Suporta os dois.
function parseCreatedAt(value) {
  if (value == null) return null;
  if (typeof value === 'number') {
    return value < 10_000_000_000 ? value * 1000 : value;
  }
  const parsed = new Date(value).getTime();
  return Number.isFinite(parsed) ? parsed : null;
}

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
    debug('onClientMessage', { conversationId, contactName, inboxName });
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
    if (!this.enabledGetter()) {
      debug('tick skip: disabled');
      return;
    }
    if (this.conversations.size === 0) {
      debug('tick: empty map, stopping interval');
      this.stop();
      return;
    }
    const now = Date.now();
    debug('tick', { size: this.conversations.size });
    Array.from(this.conversations.entries()).forEach(
      ([conversationId, entry]) => {
        const elapsedMin = (now - entry.lastClientAt) / 60000;
        debug('tick entry', {
          conversationId,
          elapsedMin: elapsedMin.toFixed(2),
          fired: Array.from(entry.firedMinutes),
        });
        THRESHOLDS.forEach(t => {
          if (elapsedMin < t.minutes) return;
          if (entry.firedMinutes.has(t.minutes)) return;
          entry.firedMinutes.add(t.minutes);
          debug('THRESHOLD HIT', {
            conversationId,
            minutes: t.minutes,
            level: t.level,
          });
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

  /**
   * Varre a lista de conversas do store e popula o tracker com aquelas
   * que estão em 'open' e tiveram o cliente como último remetente.
   * Usa o `created_at` da última msg como âncora de tempo (não Date.now()),
   * pra fechar o gap dos thresholds perdidos enquanto a aba estava fechada.
   *
   * Se a conversa já está no tracker com timestamp ≥ ao recém-lido, ignora
   * (mantém o estado dos firedMinutes — evita re-trigger em re-hidratação).
   */
  hydrateFromConversations(conversations) {
    if (!this.enabledGetter()) {
      debug('hydrate skip: disabled');
      return;
    }
    if (!Array.isArray(conversations) || conversations.length === 0) {
      debug('hydrate skip: empty list');
      return;
    }
    debug('hydrate start', { total: conversations.length });

    let hydrated = 0;
    let skippedNotOpen = 0;
    let skippedNoMsg = 0;
    let skippedAgentLast = 0;
    let skippedNoTs = 0;
    conversations.forEach(conv => {
      if (!conv || conv.status !== 'open') {
        skippedNotOpen += 1;
        return;
      }
      const lastMsg = findLastNonActivityMessage(conv);
      if (!lastMsg) {
        skippedNoMsg += 1;
        debug('hydrate skip (no last msg)', { id: conv.id });
        return;
      }

      const isClient =
        lastMsg.sender_type === 'Contact' ||
        lastMsg.message_type === 0 ||
        lastMsg.message_type === 'incoming';
      if (!isClient) {
        // Última msg foi do agente/bot — garante que não está no tracker
        if (this.conversations.has(conv.id)) {
          this.conversations.delete(conv.id);
        }
        skippedAgentLast += 1;
        return;
      }

      const lastClientAt = parseCreatedAt(lastMsg.created_at);
      if (!lastClientAt) {
        skippedNoTs += 1;
        debug('hydrate skip (bad ts)', {
          id: conv.id,
          raw: lastMsg.created_at,
        });
        return;
      }

      const existing = this.conversations.get(conv.id);
      if (existing && existing.lastClientAt >= lastClientAt) return;

      const contactName =
        (conv.meta && conv.meta.sender && conv.meta.sender.name) || '';
      const inboxName = (conv.inbox && conv.inbox.name) || '';

      this.conversations.set(conv.id, {
        lastClientAt,
        firedMinutes: new Set(),
        contactName,
        inboxName,
      });
      hydrated += 1;
    });

    debug('hydrate done', {
      hydrated,
      skippedNotOpen,
      skippedNoMsg,
      skippedAgentLast,
      skippedNoTs,
      mapSize: this.conversations.size,
    });

    if (hydrated > 0) {
      this.start();
      // Dispara imediatamente — se já passou de algum threshold, o tick
      // seguinte (20s) detectaria. Mas rodar aqui antecipa em até 20s.
      this.tick();
    }
  }
}

const inactivityAlertTracker = new InactivityAlertTracker();

export default inactivityAlertTracker;
