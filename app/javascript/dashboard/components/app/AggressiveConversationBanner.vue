<script>
import { mapGetters } from 'vuex';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import aggressiveAlert, {
  formatWaited,
} from 'dashboard/helper/aggressiveAlert';
import inactivityAlertTracker from 'dashboard/helper/inactivityAlertTracker';

// Recalcula o tempo exibido a cada 30s. O alerta guarda o INSTANTE da última
// mensagem do cliente, não a duração — então o contador precisa avançar
// sozinho em vez de congelar no valor do limiar que disparou.
const RETICK_MS = 30_000;

export default {
  name: 'AggressiveConversationBanner',
  data() {
    return {
      alerts: [],
      maxLevel: null,
      now: Date.now(),
      expanded: false,
      retickTimer: null,
    };
  },
  computed: {
    ...mapGetters({
      currentAccountId: 'getCurrentAccountId',
      allConversations: 'getAllConversations',
      currentUser: 'getCurrentUser',
    }),
    allowedInboxIds() {
      // null → sem filtro (todas); array → só essas.
      const raw =
        this.currentUser &&
        this.currentUser.ui_settings &&
        this.currentUser.ui_settings.aggressive_alert_inbox_ids;
      if (raw == null) return null;
      if (!Array.isArray(raw)) return null;
      return raw.map(id => Number(id));
    },
    hasAlerts() {
      return this.alerts.length > 0;
    },
    // Ordenado pela espera mais longa primeiro — quem esperou mais aparece antes.
    sortedAlerts() {
      return [...this.alerts].sort(
        (a, b) => this.waitedMs(b) - this.waitedMs(a)
      );
    },
    oldest() {
      return this.sortedAlerts[0] || null;
    },
    bannerClass() {
      return [
        'aggressive-banner',
        this.maxLevel ? `aggressive-banner--${this.maxLevel}` : '',
      ];
    },
    // Uma linha só. O detalhe fica atrás do "ver todas".
    headline() {
      const count = this.alerts.length;
      const oldest = this.oldest;

      if (count === 1 && oldest) {
        if (oldest.kind === 'reopened') {
          return this.$t(
            'AGGRESSIVE_CONVERSATION_BANNER.HEADLINE_REOPENED_ONE',
            { name: oldest.contactName || '—' },
            `${oldest.contactName || '—'} reabriu a conversa`
          );
        }
        return this.$t(
          'AGGRESSIVE_CONVERSATION_BANNER.HEADLINE_ONE',
          { name: oldest.contactName || '—', time: this.waitedLabel(oldest) },
          `${oldest.contactName || '—'} espera há ${this.waitedLabel(oldest)}`
        );
      }

      return this.$t(
        'AGGRESSIVE_CONVERSATION_BANNER.HEADLINE_MANY',
        { count, time: oldest ? this.waitedLabel(oldest) : '' },
        `${count} conversas esperando resposta — a mais antiga há ${
          oldest ? this.waitedLabel(oldest) : ''
        }`
      );
    },
    openLabel() {
      return this.alerts.length === 1
        ? this.$t('AGGRESSIVE_CONVERSATION_BANNER.OPEN_ONE', 'Abrir')
        : this.$t(
            'AGGRESSIVE_CONVERSATION_BANNER.OPEN_OLDEST',
            'Abrir a mais antiga'
          );
    },
    explanation() {
      return this.$t(
        'AGGRESSIVE_CONVERSATION_BANNER.EXPLANATION',
        'Este aviso só some quando a conversa for respondida. O × esconde por enquanto — volta se continuar sem resposta.'
      );
    },
  },
  watch: {
    // Rehidrata o tracker de inatividade toda vez que a lista de conversas
    // muda (inclusive no boot). Dessa forma, conversas que já estão em
    // 'open' com o cliente esperando resposta entram no tracker mesmo
    // quando o usuário só abriu a aba sem receber mensagem ao vivo.
    allConversations: {
      handler(conversations) {
        const allowed = this.allowedInboxIds;
        const filtered =
          allowed === null
            ? conversations
            : (conversations || []).filter(c =>
                allowed.includes(Number(c && c.inbox_id))
              );
        inactivityAlertTracker.hydrateFromConversations(filtered);
      },
      immediate: true,
    },
  },
  mounted() {
    emitter.on(BUS_EVENTS.AGGRESSIVE_ALERT_TRIGGER, this.refreshAlerts);
    emitter.on(BUS_EVENTS.AGGRESSIVE_ALERT_DISMISS, this.refreshAlerts);
    this.refreshAlerts();
    this.retickTimer = setInterval(() => {
      this.now = Date.now();
    }, RETICK_MS);
  },
  beforeUnmount() {
    emitter.off(BUS_EVENTS.AGGRESSIVE_ALERT_TRIGGER, this.refreshAlerts);
    emitter.off(BUS_EVENTS.AGGRESSIVE_ALERT_DISMISS, this.refreshAlerts);
    if (this.retickTimer) clearInterval(this.retickTimer);
  },
  methods: {
    refreshAlerts() {
      this.alerts = aggressiveAlert.getActiveConversations();
      this.maxLevel = aggressiveAlert.getMaxLevel();
      this.now = Date.now();
    },
    waitedMs(alert) {
      if (!alert || !alert.lastClientAt) return 0;
      return Math.max(0, this.now - alert.lastClientAt);
    },
    // Tempo REAL de espera. Antes mostrávamos o valor do limiar (5/15/28), o
    // que fazia uma conversa de 6 horas aparecer como "28 min" e a equipe
    // despriorizar justamente o caso mais grave.
    waitedLabel(alert) {
      return formatWaited(this.waitedMs(alert), {
        nowLabel: this.$t('AGGRESSIVE_CONVERSATION_BANNER.NOW', 'agora'),
      });
    },
    toggleExpanded() {
      this.expanded = !this.expanded;
    },
    openOldest() {
      if (this.oldest) this.openConversation(this.oldest);
    },
    openConversation(alert) {
      // Clica no item → abre conversa E esconde o alerta dela (mas se
      // não responder, volta a aparecer no próximo threshold).
      // Param tem que ser `conversation_id` (snake_case, como
      // declarado no path da rota); camelCase faz Vue Router não casar
      // e cair em "selecione uma conversa".
      aggressiveAlert.dismiss(alert.id);
      if (!this.currentAccountId) return;
      this.$router.push({
        name: 'inbox_conversation',
        params: {
          accountId: this.currentAccountId,
          conversation_id: alert.id,
        },
      });
    },
    dismissOne(alert) {
      aggressiveAlert.dismiss(alert.id);
    },
    itemClass(alert) {
      return ['aggressive-banner__item', `is-${alert.level}`];
    },
    contextLabel(alert) {
      if (alert.kind === 'reopened') {
        return this.$t(
          'AGGRESSIVE_CONVERSATION_BANNER.KIND_REOPENED',
          'reabriu'
        );
      }
      return this.waitedLabel(alert);
    },
  },
};
</script>

<template>
  <div v-if="hasAlerts" :class="bannerClass" role="alert" aria-live="polite">
    <div class="aggressive-banner__bar">
      <span class="aggressive-banner__dot" aria-hidden="true" />

      <span class="aggressive-banner__headline">{{ headline }}</span>

      <button type="button" class="aggressive-banner__cta" @click="openOldest">
        {{ openLabel }}
      </button>

      <button
        v-if="alerts.length > 1"
        type="button"
        class="aggressive-banner__ghost"
        :aria-expanded="expanded"
        @click="toggleExpanded"
      >
        {{
          expanded
            ? $t('AGGRESSIVE_CONVERSATION_BANNER.COLLAPSE', 'ocultar lista')
            : $t('AGGRESSIVE_CONVERSATION_BANNER.EXPAND', 'ver todas')
        }}
      </button>

      <span class="aggressive-banner__help" :title="explanation">{{
        $t('AGGRESSIVE_CONVERSATION_BANNER.HELP_ICON', '?')
      }}</span>
    </div>

    <ul v-if="expanded" class="aggressive-banner__list">
      <li
        v-for="alert in sortedAlerts"
        :key="alert.id"
        :class="itemClass(alert)"
      >
        <button
          type="button"
          class="aggressive-banner__open"
          @click="openConversation(alert)"
        >
          <span class="aggressive-banner__contact">{{
            alert.contactName || '—'
          }}</span>
          <span v-if="alert.inboxName" class="aggressive-banner__inbox">
            {{ alert.inboxName }}
          </span>
          <span class="aggressive-banner__context">{{
            contextLabel(alert)
          }}</span>
        </button>
        <button
          type="button"
          class="aggressive-banner__close"
          :aria-label="
            $t('AGGRESSIVE_CONVERSATION_BANNER.HIDE_ONE', 'Esconder')
          "
          :title="
            $t(
              'AGGRESSIVE_CONVERSATION_BANNER.HIDE_ONE_TITLE',
              'Esconde temporariamente — volta se não responder'
            )
          "
          @click="dismissOne(alert)"
        >
          {{ $t('AGGRESSIVE_CONVERSATION_BANNER.HIDE_ICON', '✕') }}
        </button>
      </li>
    </ul>
  </div>
</template>

<style lang="scss" scoped>
// Faixa de uma linha em vez de bloco de ~180px. O vermelho saturado fica
// reservado ao ponto pulsante e ao item mais crítico da lista — assim ele
// volta a significar alguma coisa em vez de ser o estado permanente da tela.
.aggressive-banner {
  position: sticky;
  top: 0;
  z-index: 9999;
  width: 100%;
  font-size: 13px;
  line-height: 1.4;
  background: #2a1a17;
  border-bottom: 1px solid #4a2620;
  color: #f0c8be;

  &--yellow {
    background: #241f14;
    border-bottom-color: #4a3d1c;
    color: #e8d5a3;
  }

  &--orange {
    background: #2a2015;
    border-bottom-color: #543a1e;
    color: #f0d0a8;
  }
}

.aggressive-banner__bar {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 16px;
  flex-wrap: wrap;
}

.aggressive-banner__dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: #e0503c;
  flex: none;
  animation: aggressive-blink 1.8s ease-in-out infinite;

  .aggressive-banner--yellow & {
    background: #d9b036;
  }
  .aggressive-banner--orange & {
    background: #e08a3c;
  }
}

@keyframes aggressive-blink {
  0%,
  100% {
    opacity: 1;
  }
  50% {
    opacity: 0.35;
  }
}

@media (prefers-reduced-motion: reduce) {
  .aggressive-banner__dot {
    animation: none;
  }
}

.aggressive-banner__headline {
  flex: 1;
  min-width: 200px;
  font-weight: 600;
  color: #ffdcd3;

  .aggressive-banner--yellow & {
    color: #f5e6bd;
  }
  .aggressive-banner--orange & {
    color: #f8e0c4;
  }
}

.aggressive-banner__cta {
  font-size: 12px;
  padding: 3px 10px;
  border: 1px solid #6e3a31;
  border-radius: 3px;
  color: #ffdcd3;
  background: transparent;
  white-space: nowrap;
  cursor: pointer;

  &:hover {
    background: rgba(255, 255, 255, 0.07);
  }
}

.aggressive-banner__ghost {
  font-size: 12px;
  background: transparent;
  border: none;
  color: inherit;
  opacity: 0.75;
  text-decoration: underline;
  cursor: pointer;
  white-space: nowrap;

  &:hover {
    opacity: 1;
  }
}

.aggressive-banner__help {
  font-size: 11px;
  opacity: 0.6;
  cursor: help;
  user-select: none;
}

.aggressive-banner__list {
  list-style: none;
  margin: 0;
  padding: 0 16px 8px;
  display: flex;
  flex-direction: column;
  gap: 1px;
}

.aggressive-banner__item {
  display: flex;
  align-items: center;
  gap: 8px;
  border-left: 3px solid transparent;
  padding-left: 8px;

  &.is-red {
    border-left-color: #e0503c;
  }
  &.is-orange {
    border-left-color: #e08a3c;
  }
  &.is-yellow {
    border-left-color: #d9b036;
  }
}

.aggressive-banner__open {
  flex: 1;
  display: flex;
  align-items: baseline;
  gap: 8px;
  background: transparent;
  border: none;
  color: inherit;
  text-align: left;
  padding: 5px 0;
  font-size: 12.5px;
  cursor: pointer;

  &:hover .aggressive-banner__contact {
    text-decoration: underline;
  }
}

.aggressive-banner__contact {
  font-weight: 600;
}

.aggressive-banner__inbox {
  opacity: 0.65;
  font-size: 11.5px;
}

.aggressive-banner__context {
  margin-left: auto;
  font-variant-numeric: tabular-nums;
  opacity: 0.85;
  font-size: 11.5px;
}

.aggressive-banner__close {
  background: transparent;
  border: none;
  color: inherit;
  opacity: 0.5;
  cursor: pointer;
  font-size: 12px;
  padding: 2px 4px;

  &:hover {
    opacity: 1;
  }
}
</style>
