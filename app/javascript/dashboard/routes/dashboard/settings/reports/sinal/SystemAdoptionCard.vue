<script setup>
// "Adoção do sistema": quanto do atendimento humano passa pelo painel do
// Chatwoot vs. sai direto pelo WhatsApp do celular (fora do sistema) —
// ranking por atendente (só painel, WhatsApp direto não tem autor) e
// distribuição por hora do dia.
import { computed } from 'vue';
import StackedBars from './StackedBars.vue';
import { formatNumber, SYSTEM_ADOPTION_COLORS } from './helpers';

const props = defineProps({
  splitItems: {
    // [{ name, value, color }] — Pelo painel / Direto no WhatsApp
    type: Array,
    default: () => [],
  },
  agents: {
    // [{ agent_id, agent_name, messages_sent }] — só respostas pelo painel
    type: Array,
    default: () => [],
  },
  whatsappDirectCount: { type: Number, default: 0 },
  hourBuckets: { type: Array, default: () => [] },
  hourTypes: { type: Array, default: () => [] },
});

const total = computed(() =>
  props.splitItems.reduce((sum, item) => sum + item.value, 0)
);

const pct = value => {
  if (!total.value) return '0%';
  return `${Math.round((value / total.value) * 100)}%`;
};

const maxAgentMessages = computed(() =>
  Math.max(1, ...props.agents.map(agent => agent.messages_sent))
);

const agentBarWidth = messagesSent =>
  `${Math.round((messagesSent / maxAgentMessages.value) * 100)}%`;
</script>

<template>
  <div
    class="rounded-xl border border-[var(--border-soft)] bg-[var(--surface)] p-5"
  >
    <div>
      <h3 class="text-[15px] font-semibold text-[var(--text)]">
        {{ $t('SINAL_REPORTS.SYSTEM_ADOPTION.TITLE') }}
      </h3>
      <p class="mt-1 text-[12.5px] text-[var(--muted)]">
        {{ $t('SINAL_REPORTS.SYSTEM_ADOPTION.SUBTITLE') }}
      </p>
    </div>

    <div v-if="!total" class="py-8 text-center text-[var(--muted-2)] text-xs">
      {{ $t('SINAL_REPORTS.SYSTEM_ADOPTION.EMPTY') }}
    </div>
    <template v-else>
      <div class="mt-4 grid grid-cols-1 sm:grid-cols-2 gap-3">
        <div
          v-for="item in splitItems"
          :key="item.name"
          class="rounded-xl border border-[var(--border-soft)] bg-[var(--surface-2)] p-4"
        >
          <div class="flex items-center justify-between gap-2">
            <span
              class="inline-flex items-center gap-1.5 text-[12px] font-semibold text-[var(--muted)]"
            >
              <span
                class="h-[9px] w-[9px] rounded-full"
                :style="{ backgroundColor: item.color }"
              />
              {{ item.name }}
            </span>
            <span class="font-mono text-[11px] text-[var(--muted-2)]">
              {{
                $t('SINAL_REPORTS.SYSTEM_ADOPTION.REPLIES_COUNT', {
                  count: formatNumber(item.value),
                })
              }}
            </span>
          </div>
          <div
            class="mt-3 font-display text-[38px] font-semibold leading-none tracking-tight text-[var(--text)]"
          >
            {{ pct(item.value) }}
          </div>
          <div
            class="mt-3 h-[7px] overflow-hidden rounded-full bg-[var(--border-soft)]"
          >
            <div
              class="h-full rounded-full"
              :style="{ width: pct(item.value), backgroundColor: item.color }"
            />
          </div>
        </div>
      </div>

      <div class="mt-4 grid grid-cols-1 xl:grid-cols-[1.3fr_1fr] gap-4">
        <div
          class="rounded-xl border border-[var(--border-soft)] bg-[var(--surface-2)] p-4"
        >
          <h4 class="text-[13px] font-semibold text-[var(--text)]">
            {{ $t('SINAL_REPORTS.SYSTEM_ADOPTION.RANKING_TITLE') }}
          </h4>
          <p class="mt-0.5 text-[11.5px] text-[var(--muted-2)]">
            {{ $t('SINAL_REPORTS.SYSTEM_ADOPTION.RANKING_SUBTITLE') }}
          </p>

          <div class="mt-3 max-h-[260px] overflow-y-auto pr-1">
            <div
              v-if="!agents.length"
              class="py-3 text-[12px] text-[var(--muted-2)]"
            >
              {{ $t('SINAL_REPORTS.SYSTEM_ADOPTION.RANKING_EMPTY') }}
            </div>
            <div
              v-for="agent in agents"
              :key="agent.agent_id"
              class="flex items-center justify-between gap-3 py-2 border-b border-[var(--border-soft)] last:border-0"
            >
              <div class="min-w-0 flex-1">
                <div
                  class="text-[13px] font-semibold text-[var(--text)] truncate"
                >
                  {{ agent.agent_name }}
                </div>
                <div
                  class="mt-1.5 h-1.5 overflow-hidden rounded-full bg-[var(--border-soft)]"
                >
                  <div
                    class="h-full rounded-full"
                    :style="{
                      width: agentBarWidth(agent.messages_sent),
                      backgroundColor: SYSTEM_ADOPTION_COLORS.panel,
                    }"
                  />
                </div>
              </div>
              <div class="text-right shrink-0">
                <div
                  class="font-display text-[15px] font-bold text-[var(--text)]"
                >
                  {{ formatNumber(agent.messages_sent) }}
                </div>
                <div class="text-[10px] text-[var(--muted-2)]">
                  {{ $t('SINAL_REPORTS.SYSTEM_ADOPTION.COL_REPLIES') }}
                </div>
              </div>
            </div>
          </div>

          <div
            class="mt-3 pt-3 border-t border-dashed border-[var(--border-soft)]"
          >
            <div class="flex items-center justify-between gap-3">
              <div class="flex min-w-0 items-center gap-2">
                <span
                  class="h-2 w-2 shrink-0 rounded-full"
                  :style="{
                    backgroundColor: SYSTEM_ADOPTION_COLORS.whatsappDirect,
                  }"
                />
                <div class="min-w-0">
                  <div class="text-[13px] font-semibold text-[var(--text)]">
                    {{ $t('SINAL_REPORTS.SYSTEM_ADOPTION.NO_AUTHOR_LABEL') }}
                  </div>
                  <div class="text-[11px] text-[var(--muted-2)]">
                    {{ $t('SINAL_REPORTS.SYSTEM_ADOPTION.NO_AUTHOR_HINT') }}
                  </div>
                </div>
              </div>
              <div class="text-right shrink-0">
                <div
                  class="font-display text-[15px] font-bold text-[var(--text)]"
                >
                  {{ formatNumber(whatsappDirectCount) }}
                </div>
                <div class="text-[10px] text-[var(--muted-2)]">
                  {{ $t('SINAL_REPORTS.SYSTEM_ADOPTION.COL_REPLIES') }}
                </div>
              </div>
            </div>
          </div>
        </div>

        <div
          class="rounded-xl border border-[var(--border-soft)] bg-[var(--surface-2)] p-4"
        >
          <h4 class="text-[13px] font-semibold text-[var(--text)]">
            {{ $t('SINAL_REPORTS.SYSTEM_ADOPTION.HOURS_TITLE') }}
          </h4>
          <p class="mt-0.5 text-[11.5px] text-[var(--muted-2)]">
            {{ $t('SINAL_REPORTS.SYSTEM_ADOPTION.HOURS_SUBTITLE') }}
          </p>
          <div class="mt-3">
            <StackedBars
              :buckets="hourBuckets"
              :types="hourTypes"
              :height="200"
            />
          </div>
          <div
            class="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-[11px] text-[var(--muted)]"
          >
            <span
              v-for="type in hourTypes"
              :key="type.key"
              class="inline-flex items-center gap-1.5"
            >
              <span
                class="h-2 w-2 rounded-full"
                :style="{ backgroundColor: type.color }"
              />
              {{ type.label }}
            </span>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
