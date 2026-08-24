<script setup>
// Mapa de calor dia da semana x hora do dia: intensidade = % de adoção do
// painel (painel / (painel + WhatsApp direto)) naquela faixa. Célula sem
// nenhuma resposta humana fica neutra (cinza) — não pinta como 0%, senão
// inventa vazamento onde nao houve atendimento nenhum.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatNumber } from './helpers';

const props = defineProps({
  cells: {
    // [{ dow, hour, panel, whatsapp_direct }] — 168 celulas (7 dias x 24h),
    // dow 0=domingo..6=sabado (convencao Postgres EXTRACT(dow)/JS Date#getDay)
    type: Array,
    default: () => [],
  },
});

const { t } = useI18n();

// Chamadas literais (nao chave dinamica) pra bater com o padrao ja usado em
// BaseHeatmap.vue (settings/reports/components/heatmaps).
const DAYS_OF_WEEK = [
  t('DAYS_OF_WEEK.SUNDAY'),
  t('DAYS_OF_WEEK.MONDAY'),
  t('DAYS_OF_WEEK.TUESDAY'),
  t('DAYS_OF_WEEK.WEDNESDAY'),
  t('DAYS_OF_WEEK.THURSDAY'),
  t('DAYS_OF_WEEK.FRIDAY'),
  t('DAYS_OF_WEEK.SATURDAY'),
];

const dowLabel = dow => DAYS_OF_WEEK[dow];
const dowShortLabel = dow => dowLabel(dow).slice(0, 3);

const hourColumns = Array.from({ length: 24 }, (_, hour) => hour);
const headerGridStyle = {
  gridTemplateColumns: '2.25rem repeat(24, minmax(0, 1fr))',
};

const grid = computed(() => {
  const byKey = new Map(
    props.cells.map(cell => [`${cell.dow}-${cell.hour}`, cell])
  );
  return Array.from({ length: 7 }, (_, dow) => ({
    dow,
    label: dowShortLabel(dow),
    hours: hourColumns.map(
      hour =>
        byKey.get(`${dow}-${hour}`) || {
          dow,
          hour,
          panel: 0,
          whatsapp_direct: 0,
        }
    ),
  }));
});

const RED = [239, 68, 68];
const AMBER = [245, 158, 11];
const GREEN = [34, 197, 94];
const LEGEND_GRADIENT_STYLE = {
  background:
    'linear-gradient(to right, rgb(239, 68, 68), rgb(245, 158, 11), rgb(34, 197, 94))',
};
const EMPTY_SWATCH_STYLE = { backgroundColor: 'var(--surface-2)' };

const lerp = (from, to, ratio) => Math.round(from + (to - from) * ratio);
const mixColor = (colorA, colorB, ratio) =>
  colorA.map((channel, i) => lerp(channel, colorB[i], ratio));

const heatColor = pct => {
  const [r, g, b] =
    pct <= 0.5
      ? mixColor(RED, AMBER, pct / 0.5)
      : mixColor(AMBER, GREEN, (pct - 0.5) / 0.5);
  return `rgb(${r}, ${g}, ${b})`;
};

const cellTotal = cell => cell.panel + cell.whatsapp_direct;
const adoptionRatio = cell =>
  cellTotal(cell) ? cell.panel / cellTotal(cell) : null;

const cellStyle = cell => {
  const ratio = adoptionRatio(cell);
  return ratio === null
    ? { backgroundColor: 'var(--surface-2)' }
    : { backgroundColor: heatColor(ratio) };
};

const hovered = ref(null);

const hoveredLabel = computed(() => {
  if (!hovered.value) return '';
  const hour = String(hovered.value.hour).padStart(2, '0');
  return `${dowLabel(hovered.value.dow)}, ${hour}h`;
});

const hoveredPct = computed(() => {
  if (!hovered.value) return null;
  const ratio = adoptionRatio(hovered.value);
  return ratio === null ? null : `${Math.round(ratio * 100)}%`;
});

const hoveredStats = computed(() => {
  if (!hovered.value || hoveredPct.value === null) return [];
  return [
    {
      label: t('SINAL_REPORTS.SYSTEM_ADOPTION.PANEL'),
      value: formatNumber(hovered.value.panel),
    },
    {
      label: t('SINAL_REPORTS.SYSTEM_ADOPTION.WHATSAPP_DIRECT'),
      value: formatNumber(hovered.value.whatsapp_direct),
    },
    {
      label: t('SINAL_REPORTS.TOTAL'),
      value: formatNumber(cellTotal(hovered.value)),
    },
    {
      label: t('SINAL_REPORTS.SYSTEM_ADOPTION.HEATMAP_ADOPTION_LABEL'),
      value: hoveredPct.value,
    },
  ];
});
</script>

<template>
  <div>
    <div class="overflow-x-auto">
      <div class="min-w-[640px]">
        <div class="grid gap-[3px]" :style="headerGridStyle">
          <div />
          <div
            v-for="hour in hourColumns"
            :key="`hour-${hour}`"
            class="text-center font-mono text-[9px] text-[var(--muted-2)]"
          >
            {{ hour % 3 === 0 ? hour : '' }}
          </div>
        </div>
        <div
          v-for="row in grid"
          :key="row.dow"
          class="mt-[3px] grid gap-[3px]"
          :style="headerGridStyle"
        >
          <div
            class="flex items-center text-[10px] font-semibold text-[var(--muted)]"
          >
            {{ row.label }}
          </div>
          <div
            v-for="cell in row.hours"
            :key="`${row.dow}-${cell.hour}`"
            class="aspect-square rounded-[3px]"
            :style="cellStyle(cell)"
            @mouseenter="hovered = cell"
            @mouseleave="hovered = null"
          />
        </div>
      </div>
    </div>

    <div
      class="mt-3 flex flex-wrap items-center gap-x-5 gap-y-2 text-[11px] text-[var(--muted)]"
    >
      <div class="flex items-center gap-2">
        <span>{{ $t('SINAL_REPORTS.SYSTEM_ADOPTION.HEATMAP_LOW') }}</span>
        <span class="h-2 w-24 rounded-full" :style="LEGEND_GRADIENT_STYLE" />
        <span>{{ $t('SINAL_REPORTS.SYSTEM_ADOPTION.HEATMAP_HIGH') }}</span>
      </div>
      <div class="flex items-center gap-1.5">
        <span
          class="h-2.5 w-2.5 rounded-[3px] border border-[var(--border-soft)]"
          :style="EMPTY_SWATCH_STYLE"
        />
        <span>{{
          $t('SINAL_REPORTS.SYSTEM_ADOPTION.HEATMAP_LEGEND_EMPTY')
        }}</span>
      </div>
    </div>

    <div
      class="mt-3 min-h-[42px] rounded-lg border border-[var(--border-soft)] bg-[var(--surface-2)] px-3 py-2.5 text-[12px]"
    >
      <template v-if="hovered">
        <div class="font-semibold text-[var(--text)]">{{ hoveredLabel }}</div>
        <div v-if="hoveredPct === null" class="mt-1 text-[var(--muted-2)]">
          {{ $t('SINAL_REPORTS.SYSTEM_ADOPTION.HEATMAP_NO_ACTIVITY') }}
        </div>
        <div v-else class="mt-1.5 grid grid-cols-2 gap-2 sm:grid-cols-4">
          <div v-for="stat in hoveredStats" :key="stat.label">
            <div class="text-[10px] text-[var(--muted-2)]">
              {{ stat.label }}
            </div>
            <div class="font-semibold text-[var(--text)]">{{ stat.value }}</div>
          </div>
        </div>
      </template>
      <span v-else class="text-[var(--muted-2)]">
        {{ $t('SINAL_REPORTS.SYSTEM_ADOPTION.HEATMAP_HOVER_HINT') }}
      </span>
    </div>
  </div>
</template>
