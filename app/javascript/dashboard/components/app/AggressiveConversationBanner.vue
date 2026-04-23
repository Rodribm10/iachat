<script>
import { mapGetters } from 'vuex';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import aggressiveAlert from 'dashboard/helper/aggressiveAlert';

export default {
  name: 'AggressiveConversationBanner',
  data() {
    return {
      alerts: [],
    };
  },
  computed: {
    ...mapGetters({ currentAccountId: 'getCurrentAccountId' }),
    hasAlerts() {
      return this.alerts.length > 0;
    },
    bannerLabel() {
      if (this.alerts.length === 1) {
        return this.$t(
          'AGGRESSIVE_CONVERSATION_BANNER.SINGLE',
          'Conversa aguardando resposta!'
        );
      }
      return this.$t(
        'AGGRESSIVE_CONVERSATION_BANNER.MULTIPLE',
        { count: this.alerts.length },
        `${this.alerts.length} conversas aguardando resposta!`
      );
    },
  },
  mounted() {
    emitter.on(BUS_EVENTS.AGGRESSIVE_ALERT_TRIGGER, this.handleTrigger);
    emitter.on(BUS_EVENTS.AGGRESSIVE_ALERT_DISMISS, this.handleDismiss);
    // Rehidrata se alertas foram disparados antes do componente montar
    this.alerts = aggressiveAlert.getActiveConversations();
  },
  beforeUnmount() {
    emitter.off(BUS_EVENTS.AGGRESSIVE_ALERT_TRIGGER, this.handleTrigger);
    emitter.off(BUS_EVENTS.AGGRESSIVE_ALERT_DISMISS, this.handleDismiss);
  },
  methods: {
    handleTrigger() {
      this.alerts = aggressiveAlert.getActiveConversations();
    },
    handleDismiss() {
      this.alerts = aggressiveAlert.getActiveConversations();
    },
    openConversation(alert) {
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
    dismissAll() {
      aggressiveAlert.dismissAll();
    },
  },
};
</script>

<template>
  <div
    v-if="hasAlerts"
    class="aggressive-banner"
    role="alert"
    aria-live="assertive"
  >
    <div class="aggressive-banner__main">
      <span class="aggressive-banner__icon">{{
        $t('AGGRESSIVE_CONVERSATION_BANNER.ALERT_ICON', '🚨')
      }}</span>
      <span class="aggressive-banner__title">{{ bannerLabel }}</span>
      <button
        type="button"
        class="aggressive-banner__dismiss-all"
        @click="dismissAll"
      >
        {{
          $t('AGGRESSIVE_CONVERSATION_BANNER.DISMISS_ALL', 'Dispensar todas')
        }}
      </button>
    </div>
    <ul class="aggressive-banner__list">
      <li
        v-for="alert in alerts"
        :key="alert.id"
        class="aggressive-banner__item"
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
          <span v-if="alert.previousStatus" class="aggressive-banner__previous">
            ·
            {{
              $t(
                `AGGRESSIVE_CONVERSATION_BANNER.FROM_${alert.previousStatus.toUpperCase()}`,
                alert.previousStatus
              )
            }}
          </span>
        </button>
        <button
          type="button"
          class="aggressive-banner__close"
          :aria-label="
            $t('AGGRESSIVE_CONVERSATION_BANNER.DISMISS_ONE', 'Dispensar')
          "
          @click="dismissOne(alert)"
        >
          {{ $t('AGGRESSIVE_CONVERSATION_BANNER.CLOSE_ICON', '×') }}
        </button>
      </li>
    </ul>
  </div>
</template>

<style lang="scss" scoped>
@keyframes aggressive-pulse {
  0%,
  100% {
    background-color: #b91c1c;
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
  background-color: #b91c1c;
  color: #ffffff;
  padding: 12px 16px;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.25);
  animation: aggressive-pulse 1.2s ease-in-out infinite;
  font-weight: 600;
}

.aggressive-banner__main {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-bottom: 8px;
}

.aggressive-banner__icon {
  font-size: 24px;
  line-height: 1;
}

.aggressive-banner__title {
  font-size: 16px;
  flex: 1;
}

.aggressive-banner__dismiss-all {
  background: rgba(255, 255, 255, 0.2);
  color: #ffffff;
  border: 1px solid rgba(255, 255, 255, 0.5);
  border-radius: 4px;
  padding: 6px 12px;
  cursor: pointer;
  font-size: 13px;
  font-weight: 500;
  transition: background 0.15s ease;
}

.aggressive-banner__dismiss-all:hover {
  background: rgba(255, 255, 255, 0.35);
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
  background: rgba(0, 0, 0, 0.25);
  border-radius: 4px;
  overflow: hidden;
}

.aggressive-banner__open {
  background: transparent;
  color: #ffffff;
  border: none;
  padding: 6px 12px;
  cursor: pointer;
  font-size: 13px;
  font-weight: 500;
  text-align: left;
  display: flex;
  align-items: center;
  gap: 4px;
}

.aggressive-banner__open:hover {
  background: rgba(255, 255, 255, 0.15);
}

.aggressive-banner__contact {
  font-weight: 700;
}

.aggressive-banner__inbox,
.aggressive-banner__previous {
  opacity: 0.85;
  font-weight: 400;
}

.aggressive-banner__close {
  background: transparent;
  color: #ffffff;
  border: none;
  border-left: 1px solid rgba(255, 255, 255, 0.2);
  padding: 6px 10px;
  cursor: pointer;
  font-size: 18px;
  line-height: 1;
  font-weight: 700;
}

.aggressive-banner__close:hover {
  background: rgba(255, 255, 255, 0.2);
}
</style>
