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

// Cor por severidade, nos tokens do design system (não em hex) — assim o aviso
// acompanha tema claro/escuro em vez de ser um retângulo escuro fixo por cima
// de um dashboard claro.
const DOT_CLASS = {
  yellow: 'bg-n-amber-9',
  orange: 'bg-n-amber-10',
  red: 'bg-n-ruby-9',
};

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
    dotClass() {
      return DOT_CLASS[this.maxLevel] || DOT_CLASS.yellow;
    },
    isCritical() {
      return this.maxLevel === 'red';
    },
    // Uma linha só. O detalhe fica atrás do "ver todas".
    headline() {
      const count = this.alerts.length;
      const oldest = this.oldest;

      if (count === 1 && oldest) {
        if (oldest.kind === 'reopened') {
          return this.$t(
            'AGGRESSIVE_CONVERSATION_BANNER.HEADLINE_REOPENED_ONE',
            { name: oldest.contactName || '—' }
          );
        }
        return this.$t('AGGRESSIVE_CONVERSATION_BANNER.HEADLINE_ONE', {
          name: oldest.contactName || '—',
          time: this.waitedLabel(oldest),
        });
      }

      return this.$t('AGGRESSIVE_CONVERSATION_BANNER.HEADLINE_MANY', {
        count,
        time: oldest ? this.waitedLabel(oldest) : '',
      });
    },
    openLabel() {
      return this.alerts.length === 1
        ? this.$t('AGGRESSIVE_CONVERSATION_BANNER.OPEN_ONE')
        : this.$t('AGGRESSIVE_CONVERSATION_BANNER.OPEN_OLDEST');
    },
    explanation() {
      return this.$t('AGGRESSIVE_CONVERSATION_BANNER.EXPLANATION');
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
      if (!this.alerts.length) this.expanded = false;
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
        nowLabel: this.$t('AGGRESSIVE_CONVERSATION_BANNER.NOW'),
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
    dotClassFor(alert) {
      return DOT_CLASS[alert.level] || DOT_CLASS.yellow;
    },
    contextLabel(alert) {
      if (alert.kind === 'reopened') {
        return this.$t('AGGRESSIVE_CONVERSATION_BANNER.KIND_REOPENED');
      }
      return this.waitedLabel(alert);
    },
  },
};
</script>

<template>
  <!--
    Cartão flutuante no canto, não faixa no topo. A faixa ocupava a largura
    inteira do app e empurrava o conteúdo — pelo tamanho parecia falha de
    sistema, e como estava sempre lá deixou de ser lida. Aqui o aviso fica
    perto da mão, cabe numa linha e some sozinho quando a fila zera.
  -->
  <div
    v-if="hasAlerts"
    class="fixed z-50 flex flex-col items-end gap-2 bottom-4 ltr:right-4 rtl:left-4"
    role="status"
    aria-live="polite"
  >
    <!-- Lista completa: abre PRA CIMA, para a pill não pular de lugar. -->
    <transition name="alert-list">
      <ul
        v-if="expanded"
        class="flex flex-col w-[min(22rem,calc(100vw-2rem))] gap-px p-1.5 m-0 overflow-y-auto list-none shadow-lg outline outline-1 outline-n-container rounded-xl bg-n-alpha-3 backdrop-blur-[100px] max-h-80"
      >
        <li
          v-for="alert in sortedAlerts"
          :key="alert.id"
          class="flex items-center gap-1"
        >
          <button
            type="button"
            class="flex items-center flex-1 min-w-0 gap-2 px-2 py-1.5 text-left transition-colors rounded-lg reset-base hover:bg-n-alpha-2"
            @click="openConversation(alert)"
          >
            <span
              :class="dotClassFor(alert)"
              class="flex-none rounded-full size-1.5"
              aria-hidden="true"
            />
            <span class="text-sm truncate text-n-slate-12">
              {{ alert.contactName || '—' }}
            </span>
            <span
              v-if="alert.inboxName"
              class="text-xs truncate text-n-slate-10"
            >
              {{ alert.inboxName }}
            </span>
            <span
              class="ltr:ml-auto rtl:mr-auto text-xs tabular-nums text-n-slate-11 flex-none"
            >
              {{ contextLabel(alert) }}
            </span>
          </button>
          <button
            type="button"
            class="flex-none p-1 transition-colors rounded-md reset-base text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2"
            :aria-label="$t('AGGRESSIVE_CONVERSATION_BANNER.HIDE_ONE')"
            :title="$t('AGGRESSIVE_CONVERSATION_BANNER.HIDE_ONE_TITLE')"
            @click="dismissOne(alert)"
          >
            <span class="i-lucide-x size-3.5" />
          </button>
        </li>
      </ul>
    </transition>

    <!-- A pill: uma linha, sempre do mesmo tamanho. -->
    <div
      class="flex items-center h-10 gap-2.5 ltr:pl-3.5 ltr:pr-1.5 rtl:pr-3.5 rtl:pl-1.5 rounded-full shadow-lg outline outline-1 bg-n-alpha-3 backdrop-blur-[100px] max-w-[min(26rem,calc(100vw-2rem))]"
      :class="isCritical ? 'outline-n-ruby-8' : 'outline-n-container'"
    >
      <span
        :class="[dotClass, { 'alert-dot--pulse': isCritical }]"
        class="flex-none rounded-full size-2"
        aria-hidden="true"
      />

      <span class="text-sm truncate text-n-slate-12">{{ headline }}</span>

      <div class="flex items-center flex-none gap-0.5 ltr:ml-auto rtl:mr-auto">
        <button
          type="button"
          class="h-7 px-2.5 text-xs font-medium transition-colors rounded-full reset-base text-n-slate-12 hover:bg-n-alpha-2"
          @click="openOldest"
        >
          {{ openLabel }}
        </button>

        <button
          v-if="alerts.length > 1"
          type="button"
          class="flex items-center justify-center transition-colors rounded-full reset-base size-7 text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-2"
          :aria-expanded="expanded"
          :aria-label="
            expanded
              ? $t('AGGRESSIVE_CONVERSATION_BANNER.COLLAPSE')
              : $t('AGGRESSIVE_CONVERSATION_BANNER.EXPAND')
          "
          :title="
            expanded
              ? $t('AGGRESSIVE_CONVERSATION_BANNER.COLLAPSE')
              : $t('AGGRESSIVE_CONVERSATION_BANNER.EXPAND')
          "
          @click="toggleExpanded"
        >
          <span
            class="size-3.5 transition-transform"
            :class="expanded ? 'i-lucide-chevron-down' : 'i-lucide-chevron-up'"
          />
        </button>

        <span
          class="flex items-center justify-center cursor-help size-7 text-n-slate-10"
          :title="explanation"
        >
          <span class="i-lucide-info size-3.5" />
        </span>
      </div>
    </div>
  </div>
</template>

<style lang="scss" scoped>
// Pulso só no nível crítico — e discreto. O ponto piscando em tudo fazia o
// vermelho virar o estado permanente da tela, que é como um alerta para de
// significar alguma coisa.
.alert-dot--pulse {
  animation: alert-dot-pulse 2.4s ease-in-out infinite;
}

@keyframes alert-dot-pulse {
  0%,
  100% {
    opacity: 1;
  }
  50% {
    opacity: 0.4;
  }
}

.alert-list-enter-active,
.alert-list-leave-active {
  transition:
    opacity 0.15s ease,
    transform 0.15s ease;
}

.alert-list-enter-from,
.alert-list-leave-to {
  opacity: 0;
  transform: translateY(0.5rem);
}

@media (prefers-reduced-motion: reduce) {
  .alert-dot--pulse {
    animation: none;
  }

  .alert-list-enter-active,
  .alert-list-leave-active {
    transition: none;
  }
}
</style>
