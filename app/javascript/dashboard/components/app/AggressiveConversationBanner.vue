<script>
import { mapGetters } from 'vuex';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import aggressiveAlert from 'dashboard/helper/aggressiveAlert';
import inactivityAlertTracker from 'dashboard/helper/inactivityAlertTracker';

export default {
  name: 'AggressiveConversationBanner',
  data() {
    return {
      alerts: [],
      maxLevel: null,
    };
  },
  computed: {
    ...mapGetters({
      currentAccountId: 'getCurrentAccountId',
      allConversations: 'getAllConversations',
    }),
    hasAlerts() {
      return this.alerts.length > 0;
    },
    bannerClass() {
      return [
        'aggressive-banner',
        this.maxLevel ? `aggressive-banner--${this.maxLevel}` : '',
      ];
    },
    bannerHeadline() {
      const count = this.alerts.length;
      if (count === 1) {
        const a = this.alerts[0];
        if (a.kind === 'reopened') {
          return this.$t(
            'AGGRESSIVE_CONVERSATION_BANNER.HEADLINE_REOPENED',
            'Conversa reaberta — responda agora'
          );
        }
        // inactivity — mostra tempo
        if (a.minutes >= 28) {
          return this.$t(
            'AGGRESSIVE_CONVERSATION_BANNER.HEADLINE_28',
            { minutes: a.minutes },
            `🚨 ${a.minutes} MIN SEM RESPOSTA — conversa fecha em breve`
          );
        }
        if (a.minutes >= 15) {
          return this.$t(
            'AGGRESSIVE_CONVERSATION_BANNER.HEADLINE_15',
            { minutes: a.minutes },
            `⚠️ ${a.minutes} MIN SEM RESPOSTA`
          );
        }
        return this.$t(
          'AGGRESSIVE_CONVERSATION_BANNER.HEADLINE_5',
          { minutes: a.minutes },
          `⏰ ${a.minutes} min sem resposta`
        );
      }
      return this.$t(
        'AGGRESSIVE_CONVERSATION_BANNER.HEADLINE_MULTIPLE',
        { count },
        `🚨 ${count} conversas aguardando resposta`
      );
    },
    explanation() {
      return this.$t(
        'AGGRESSIVE_CONVERSATION_BANNER.EXPLANATION',
        'Este alerta só some quando você RESPONDER a conversa. Clicar no × esconde temporariamente.'
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
        inactivityAlertTracker.hydrateFromConversations(conversations);
      },
      immediate: true,
    },
  },
  mounted() {
    emitter.on(BUS_EVENTS.AGGRESSIVE_ALERT_TRIGGER, this.refreshAlerts);
    emitter.on(BUS_EVENTS.AGGRESSIVE_ALERT_DISMISS, this.refreshAlerts);
    // Rehidrata se alertas foram disparados antes do componente montar
    this.refreshAlerts();
  },
  beforeUnmount() {
    emitter.off(BUS_EVENTS.AGGRESSIVE_ALERT_TRIGGER, this.refreshAlerts);
    emitter.off(BUS_EVENTS.AGGRESSIVE_ALERT_DISMISS, this.refreshAlerts);
  },
  methods: {
    refreshAlerts() {
      this.alerts = aggressiveAlert.getActiveConversations();
      this.maxLevel = aggressiveAlert.getMaxLevel();
    },
    openConversation(alert) {
      // Clica no item → abre conversa E esconde o alerta dela (mas se
      // não responder, volta a aparecer no próximo threshold).
      aggressiveAlert.dismiss(alert.id);
      if (!this.currentAccountId) return;
      this.$router.push({
        name: 'inbox_conversation',
        params: { accountId: this.currentAccountId, conversationId: alert.id },
      });
    },
    dismissOne(alert) {
      aggressiveAlert.dismiss(alert.id);
    },
    alertItemClass(alert) {
      return [
        'aggressive-banner__item',
        `aggressive-banner__item--${alert.level}`,
      ];
    },
    alertContextLabel(alert) {
      if (alert.kind === 'reopened') {
        return this.$t(
          'AGGRESSIVE_CONVERSATION_BANNER.KIND_REOPENED',
          'reabriu'
        );
      }
      return this.$t(
        'AGGRESSIVE_CONVERSATION_BANNER.KIND_WAITING',
        { minutes: alert.minutes || '?' },
        `${alert.minutes || '?'} min sem resposta`
      );
    },
  },
};
</script>

<template>
  <div v-if="hasAlerts" :class="bannerClass" role="alert" aria-live="assertive">
    <div class="aggressive-banner__headline">
      {{ bannerHeadline }}
    </div>
    <div class="aggressive-banner__explanation">
      {{ explanation }}
    </div>
    <ul class="aggressive-banner__list">
      <li
        v-for="alert in alerts"
        :key="alert.id"
        :class="alertItemClass(alert)"
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
            · {{ alert.inboxName }}
          </span>
          <span class="aggressive-banner__context">
            · {{ alertContextLabel(alert) }}
          </span>
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
          {{ $t('AGGRESSIVE_CONVERSATION_BANNER.HIDE_ICON', '×') }}
        </button>
      </li>
    </ul>
  </div>
</template>

<style lang="scss" scoped>
@keyframes aggressive-pulse-yellow {
  0%,
  100% {
    background-color: #eab308;
  }
  50% {
    background-color: #fbbf24;
  }
}
@keyframes aggressive-pulse-orange {
  0%,
  100% {
    background-color: #c2410c;
  }
  50% {
    background-color: #f97316;
  }
}
@keyframes aggressive-pulse-red {
  0%,
  100% {
    background-color: #991b1b;
  }
  50% {
    background-color: #ef4444;
  }
}

.aggressive-banner {
  position: sticky;
  top: 0;
  z-index: 9999;
  width: 100%;
  color: #ffffff;
  padding: 14px 20px;
  box-shadow: 0 4px 18px rgba(0, 0, 0, 0.35);
  font-weight: 700;
}

.aggressive-banner--yellow {
  background-color: #eab308;
  color: #1f2937;
}
.aggressive-banner--orange {
  background-color: #c2410c;
  animation: aggressive-pulse-orange 1.4s ease-in-out infinite;
}
.aggressive-banner--red {
  background-color: #991b1b;
  animation: aggressive-pulse-red 0.9s ease-in-out infinite;
}

.aggressive-banner__headline {
  font-size: 22px;
  line-height: 1.2;
  margin-bottom: 4px;
  letter-spacing: 0.5px;
  text-shadow: 0 1px 2px rgba(0, 0, 0, 0.25);
}

.aggressive-banner__explanation {
  font-size: 13px;
  font-weight: 500;
  opacity: 0.92;
  margin-bottom: 10px;
}

.aggressive-banner__list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

.aggressive-banner__item {
  display: flex;
  align-items: center;
  background: rgba(0, 0, 0, 0.3);
  border-radius: 6px;
  overflow: hidden;
  font-size: 14px;
}

.aggressive-banner__item--yellow {
  background: rgba(0, 0, 0, 0.18);
}

.aggressive-banner__open {
  background: transparent;
  color: inherit;
  border: none;
  padding: 8px 12px;
  cursor: pointer;
  font-weight: 600;
  text-align: left;
  display: flex;
  align-items: center;
  gap: 4px;
}
.aggressive-banner__open:hover {
  background: rgba(255, 255, 255, 0.15);
}

.aggressive-banner__contact {
  font-weight: 800;
}
.aggressive-banner__inbox,
.aggressive-banner__context {
  opacity: 0.9;
  font-weight: 500;
}

.aggressive-banner__close {
  background: transparent;
  color: inherit;
  border: none;
  border-left: 1px solid rgba(255, 255, 255, 0.25);
  padding: 8px 12px;
  cursor: pointer;
  font-size: 20px;
  line-height: 1;
  font-weight: 800;
}
.aggressive-banner__close:hover {
  background: rgba(255, 255, 255, 0.2);
}
</style>
