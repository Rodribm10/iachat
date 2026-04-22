<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';

const props = defineProps({
  contactId: { type: [String, Number], required: true },
});

const { t } = useI18n();
const store = useStore();

const contact = computed(() =>
  store.getters['contacts/getContact'](props.contactId)
);

const summary = computed(() => {
  if (!contact.value) return null;
  return {
    interactions: contact.value.interactions_count ?? 0,
    oneShots: contact.value.one_shot_consultations_count ?? 0,
    pixGenerated: contact.value.pix_generated_count ?? 0,
    reservationsPaid: contact.value.reservations_paid_count ?? 0,
    lastInteractionAt: contact.value.last_interaction_at ?? null,
    daysSince: contact.value.days_since_last_interaction ?? null,
    isRecurring: contact.value.is_recurring ?? false,
  };
});

const status = computed(() => {
  const s = summary.value;
  const B = 'CAPTAIN_REPORTS.RETENTION.BADGE';
  if (!s || s.interactions === 0)
    return { label: t(`${B}.STATUS_FIRST`), tone: 'slate' };
  if (s.daysSince !== null && s.daysSince > 180)
    return { label: t(`${B}.STATUS_INACTIVE`), tone: 'rose' };
  if (s.daysSince !== null && s.daysSince > 90)
    return { label: t(`${B}.STATUS_AT_RISK`), tone: 'orange' };
  if (s.daysSince !== null && s.daysSince > 30)
    return { label: t(`${B}.STATUS_SLEEPING`), tone: 'amber' };
  if (s.isRecurring)
    return { label: t(`${B}.STATUS_RECURRING`), tone: 'emerald' };
  return { label: t(`${B}.STATUS_ACTIVE`), tone: 'sky' };
});

const toneClass = {
  slate: 'bg-slate-100 text-slate-700 dark:bg-slate-700 dark:text-slate-200',
  emerald:
    'bg-emerald-100 text-emerald-700 dark:bg-emerald-900/40 dark:text-emerald-300',
  sky: 'bg-sky-100 text-sky-700 dark:bg-sky-900/40 dark:text-sky-300',
  amber: 'bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-200',
  orange:
    'bg-orange-100 text-orange-800 dark:bg-orange-900/40 dark:text-orange-200',
  rose: 'bg-rose-100 text-rose-700 dark:bg-rose-900/40 dark:text-rose-300',
};

function formatDaysSince(days) {
  const B = 'CAPTAIN_REPORTS.RETENTION.BADGE';
  if (days === null || days === undefined) return '';
  if (days === 0) return t(`${B}.DAYS_TODAY`);
  if (days === 1) return t(`${B}.DAYS_YESTERDAY`);
  if (days < 30) return t(`${B}.DAYS_RECENT`, { days });
  if (days < 60) return t(`${B}.DAYS_ONE_MONTH`);
  if (days < 365)
    return t(`${B}.DAYS_MONTHS`, { months: Math.round(days / 30) });
  return t(`${B}.DAYS_YEARS`, { years: Math.round(days / 365) });
}

const interactionsLabel = computed(() => {
  const s = summary.value;
  if (!s) return '';
  const parts = t('CAPTAIN_REPORTS.RETENTION.BADGE.INTERACTIONS_LABEL').split(
    ' | '
  );
  return s.interactions === 1 ? parts[0] : parts[1] || parts[0];
});
</script>

<template>
  <div
    v-if="summary"
    class="mb-3 rounded-lg border border-slate-200 bg-slate-50/50 px-3 py-2.5 dark:border-slate-700 dark:bg-slate-800/40"
  >
    <div class="mb-1.5 flex items-center justify-between">
      <span
        :class="toneClass[status.tone]"
        class="rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide"
      >
        {{ status.label }}
      </span>
      <span v-if="summary.lastInteractionAt" class="text-[10px] text-slate-500">
        {{
          $t('CAPTAIN_REPORTS.RETENTION.BADGE.LAST_INTERACTION', {
            days: formatDaysSince(summary.daysSince),
          })
        }}
      </span>
    </div>
    <div
      class="flex flex-wrap gap-x-4 gap-y-1 text-xs text-slate-600 dark:text-slate-300"
    >
      <span :title="$t('CAPTAIN_REPORTS.RETENTION.BADGE.INTERACTIONS_TITLE')">
        <strong class="text-slate-900 dark:text-slate-100">{{
          summary.interactions
        }}</strong>
        {{ interactionsLabel }}
      </span>
      <span
        v-if="summary.oneShots > 0"
        :title="$t('CAPTAIN_REPORTS.RETENTION.BADGE.ONE_SHOT_TITLE')"
      >
        <strong class="text-slate-900 dark:text-slate-100">{{
          summary.oneShots
        }}</strong>
        {{ $t('CAPTAIN_REPORTS.RETENTION.BADGE.ONE_SHOT_LABEL') }}
      </span>
      <span
        v-if="summary.pixGenerated > 0"
        :title="$t('CAPTAIN_REPORTS.RETENTION.BADGE.PIX_TITLE')"
      >
        <strong class="text-slate-900 dark:text-slate-100">{{
          summary.reservationsPaid
        }}</strong
        >/{{ summary.pixGenerated }}
        {{ $t('CAPTAIN_REPORTS.RETENTION.BADGE.PIX_LABEL') }}
      </span>
    </div>
  </div>
  <div v-else />
</template>
