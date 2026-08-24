<script setup>
// "Modelo de atendimento": participação da IA e da equipe por conversa —
// Só IA / Misto / Só humano (réplica da branch relatorios-visuais do Sinal).
import { computed } from 'vue';
import DonutChart from './DonutChart.vue';
import { formatNumber } from './helpers';

const props = defineProps({
  items: {
    // [{ name, value, color }] — Só IA / Misto / Só humano
    type: Array,
    default: () => [],
  },
  totalConversations: { type: Number, default: 0 },
  unclassified: { type: Number, default: 0 },
  contacts: { type: Number, default: 0 },
  contactsAiAttended: { type: Number, default: 0 },
  newContacts: { type: Number, default: 0 },
  newContactsAiAttended: { type: Number, default: 0 },
});

const classified = computed(() =>
  props.items.reduce((sum, item) => sum + item.value, 0)
);

const pct = (value, total) => {
  if (!total) return '0%';
  return `${Math.round((value / total) * 100)}%`;
};
</script>

<template>
  <div
    class="mb-4 rounded-xl border border-[var(--border-soft)] bg-[var(--surface)] p-5"
  >
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div>
        <h3 class="text-[15px] font-semibold text-[var(--text)]">
          {{ $t('SINAL_REPORTS.SERVICE_MODE.TITLE') }}
        </h3>
        <p class="mt-1 text-[12.5px] text-[var(--muted)]">
          {{ $t('SINAL_REPORTS.SERVICE_MODE.SUBTITLE') }}
        </p>
      </div>
      <span
        class="rounded-lg border border-[var(--border-soft)] bg-[var(--surface-2)] px-2.5 py-1 text-[11px] font-medium text-[var(--muted)]"
      >
        {{
          $t('SINAL_REPORTS.SERVICE_MODE.CLASSIFIED', {
            count: formatNumber(classified),
          })
        }}
      </span>
    </div>

    <div
      class="mt-5 grid grid-cols-1 xl:grid-cols-[250px_minmax(0,1fr)] gap-4 items-stretch"
    >
      <div
        class="rounded-xl border border-[var(--border-soft)] bg-[var(--surface-2)] px-3 py-2"
      >
        <DonutChart
          :items="items"
          :unit="$t('SINAL_REPORTS.SERVICE_MODE.UNIT')"
          :size="202"
        />
      </div>
      <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
        <div
          v-for="item in items"
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
                $t('SINAL_REPORTS.SERVICE_MODE.CONVERSATIONS_COUNT', {
                  count: formatNumber(item.value),
                })
              }}
            </span>
          </div>
          <div
            class="mt-3 font-display text-[38px] font-semibold leading-none tracking-tight text-[var(--text)]"
          >
            {{ pct(item.value, classified) }}
          </div>
          <div
            class="mt-3 h-[7px] overflow-hidden rounded-full bg-[var(--border-soft)]"
          >
            <div
              class="h-full rounded-full"
              :style="{
                width: pct(item.value, classified),
                backgroundColor: item.color,
              }"
            />
          </div>
        </div>
      </div>
    </div>

    <p class="mt-4 text-[11.5px] text-[var(--muted-2)]">
      {{
        unclassified > 0
          ? $t('SINAL_REPORTS.SERVICE_MODE.BASE_WITH_UNCLASSIFIED', {
              total: formatNumber(totalConversations),
              unclassified: formatNumber(unclassified),
            })
          : $t('SINAL_REPORTS.SERVICE_MODE.BASE', {
              total: formatNumber(totalConversations),
            })
      }}
    </p>

    <div class="mt-3 grid grid-cols-1 sm:grid-cols-2 gap-3">
      <div
        class="rounded-[10px] border border-[var(--border-soft)] bg-[var(--surface-2)] px-3.5 py-2.5"
      >
        <div
          class="text-[11px] font-semibold uppercase tracking-wider text-[var(--muted-2)]"
        >
          {{ $t('SINAL_REPORTS.SERVICE_MODE.ALL_CONTACTS') }}
        </div>
        <div class="mt-1 text-[13px] text-[var(--muted)]">
          {{ $t('SINAL_REPORTS.SERVICE_MODE.AI_ATTENDED_PREFIX') }}
          <strong class="text-[var(--accent)]">
            {{
              $t('SINAL_REPORTS.SERVICE_MODE.AI_ATTENDED_VALUE', {
                attended: formatNumber(contactsAiAttended),
                total: formatNumber(contacts),
                pct: pct(contactsAiAttended, contacts),
              })
            }}
          </strong>
        </div>
      </div>
      <div
        class="rounded-[10px] border border-[var(--border-soft)] bg-[var(--surface-2)] px-3.5 py-2.5"
      >
        <div
          class="text-[11px] font-semibold uppercase tracking-wider text-[var(--muted-2)]"
        >
          {{ $t('SINAL_REPORTS.SERVICE_MODE.NEW_LEADS') }}
        </div>
        <div class="mt-1 text-[13px] text-[var(--muted)]">
          {{ $t('SINAL_REPORTS.SERVICE_MODE.AI_ATTENDED_PREFIX') }}
          <strong class="text-[var(--accent)]">
            {{
              $t('SINAL_REPORTS.SERVICE_MODE.AI_ATTENDED_VALUE', {
                attended: formatNumber(newContactsAiAttended),
                total: formatNumber(newContacts),
                pct: pct(newContactsAiAttended, newContacts),
              })
            }}
          </strong>
        </div>
      </div>
    </div>

    <p class="mt-2 text-[11px] text-[var(--muted-2)]">
      {{ $t('SINAL_REPORTS.SERVICE_MODE.FOOTNOTE') }}
    </p>
  </div>
</template>
