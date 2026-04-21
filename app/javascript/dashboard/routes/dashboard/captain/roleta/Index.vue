<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import PageLayout from 'dashboard/components-next/captain/PageLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import roletaApi from 'dashboard/api/captain/roleta';

const { t } = useI18n();

const tab = ref('resgate');

const code = ref('');
const notes = ref('');
const submitting = ref(false);
const loadingPending = ref(false);
const pending = ref([]);
const lastResult = ref(null);

const reportPeriod = ref(7);
const report = ref(null);
const loadingReport = ref(false);

const canSubmit = computed(
  () => code.value.trim().length >= 4 && !submitting.value
);

const ERROR_KEYS = {
  empty_code: 'CAPTAIN_ROLETA.REDEEM.ERROR_EMPTY_CODE',
  not_found: 'CAPTAIN_ROLETA.REDEEM.ERROR_NOT_FOUND',
  already_redeemed: 'CAPTAIN_ROLETA.REDEEM.ERROR_ALREADY_REDEEMED',
  no_prize_to_claim: 'CAPTAIN_ROLETA.REDEEM.ERROR_NO_PRIZE',
  no_receptionist: 'CAPTAIN_ROLETA.REDEEM.ERROR_NO_RECEPTIONIST',
  rpc_failed: 'CAPTAIN_ROLETA.REDEEM.ERROR_RPC_FAILED',
  exception: 'CAPTAIN_ROLETA.REDEEM.ERROR_EXCEPTION',
};

function errorText(errCode) {
  const key = ERROR_KEYS[errCode];
  return key ? t(key) : t('CAPTAIN_ROLETA.REDEEM.ERROR_DEFAULT');
}

function fmtDateTime(iso) {
  if (!iso) return '';
  return new Date(iso).toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
}

function fmtPrize(row) {
  if (row.prize_tipo === 'desconto_percentual') {
    return `${Number(row.prize_valor)}% OFF`;
  }
  return row.prize_nome;
}

function fmtCurrency(v) {
  return (Number(v) || 0).toLocaleString('pt-BR', {
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  });
}

async function loadPending() {
  loadingPending.value = true;
  try {
    const res = await roletaApi.pending({ days_back: 7 });
    pending.value = res.data?.pending ?? [];
  } catch (err) {
    useAlert(t('CAPTAIN_ROLETA.HISTORY.LOAD_ERROR'));
  } finally {
    loadingPending.value = false;
  }
}

async function submitRedeem() {
  if (!canSubmit.value) return;
  submitting.value = true;
  lastResult.value = null;
  try {
    const { data } = await roletaApi.redeem(code.value.trim(), notes.value);
    lastResult.value = { success: true, ...data.result };
    useAlert(
      t('CAPTAIN_ROLETA.REDEEM.SUCCESS_PREFIX').replace(
        '{prize}',
        fmtPrize(data.result)
      )
    );
    code.value = '';
    notes.value = '';
    await loadPending();
  } catch (err) {
    const resp = err?.response?.data;
    const errCode = resp?.error_code;
    lastResult.value = {
      success: false,
      error_code: errCode,
      ...(resp?.result ?? {}),
    };
    useAlert(errorText(errCode));
  } finally {
    submitting.value = false;
  }
}

async function loadReport() {
  loadingReport.value = true;
  try {
    const { data } = await roletaApi.weeklyReport(reportPeriod.value);
    report.value = data;
  } catch (err) {
    useAlert(t('CAPTAIN_ROLETA.REPORT.LOAD_ERROR'));
  } finally {
    loadingReport.value = false;
  }
}

function switchTab(newTab) {
  tab.value = newTab;
  if (newTab === 'relatorio' && !report.value) loadReport();
}

onMounted(() => {
  loadPending();
});
</script>

<template>
  <PageLayout
    :header-title="t('CAPTAIN_ROLETA.HEADER')"
    :show-assistant-switcher="false"
    :show-pagination-footer="false"
    :is-empty="false"
    :is-fetching="false"
  >
    <template #body>
      <div class="flex flex-col gap-6 py-4">
        <div class="flex gap-1 border-b border-n-weak">
          <button
            class="px-4 py-2 text-sm font-medium border-b-2 transition"
            :class="[
              tab === 'resgate'
                ? 'border-n-brand text-n-brand'
                : 'border-transparent text-n-slate-11 hover:text-n-slate-12',
            ]"
            @click="switchTab('resgate')"
          >
            {{ t('CAPTAIN_ROLETA.TAB_REDEEM') }}
          </button>
          <button
            class="px-4 py-2 text-sm font-medium border-b-2 transition"
            :class="[
              tab === 'relatorio'
                ? 'border-n-brand text-n-brand'
                : 'border-transparent text-n-slate-11 hover:text-n-slate-12',
            ]"
            @click="switchTab('relatorio')"
          >
            {{ t('CAPTAIN_ROLETA.TAB_REPORT') }}
          </button>
        </div>

        <template v-if="tab === 'resgate'">
          <div
            class="rounded-xl border border-n-weak bg-n-alpha-black2 p-6 shadow-sm"
          >
            <h2 class="text-lg font-semibold text-n-slate-12 mb-1">
              {{ t('CAPTAIN_ROLETA.REDEEM.TITLE') }}
            </h2>
            <p class="text-sm text-n-slate-11 mb-4">
              {{ t('CAPTAIN_ROLETA.REDEEM.DESC') }}
            </p>

            <form class="flex flex-col gap-3" @submit.prevent="submitRedeem">
              <div>
                <label
                  class="block text-xs font-medium text-n-slate-11 mb-1 uppercase tracking-wide"
                >
                  {{ t('CAPTAIN_ROLETA.REDEEM.CODE_LABEL') }}
                </label>
                <Input
                  v-model="code"
                  :placeholder="t('CAPTAIN_ROLETA.REDEEM.CODE_PLACEHOLDER')"
                  class="uppercase font-mono tracking-widest text-lg"
                  maxlength="12"
                  autofocus
                />
              </div>

              <div>
                <label
                  class="block text-xs font-medium text-n-slate-11 mb-1 uppercase tracking-wide"
                >
                  {{ t('CAPTAIN_ROLETA.REDEEM.NOTES_LABEL') }}
                </label>
                <Input
                  v-model="notes"
                  :placeholder="t('CAPTAIN_ROLETA.REDEEM.NOTES_PLACEHOLDER')"
                />
              </div>

              <div class="flex justify-end mt-2">
                <Button
                  type="submit"
                  :label="
                    submitting
                      ? t('CAPTAIN_ROLETA.REDEEM.SUBMITTING')
                      : t('CAPTAIN_ROLETA.REDEEM.SUBMIT')
                  "
                  :disabled="!canSubmit"
                  :is-loading="submitting"
                />
              </div>
            </form>

            <div
              v-if="lastResult"
              class="mt-4 rounded-lg border p-3 text-sm"
              :class="[
                lastResult.success
                  ? 'border-n-teal-7 bg-n-teal-3 text-n-teal-12'
                  : 'border-n-ruby-7 bg-n-ruby-3 text-n-ruby-12',
              ]"
            >
              <div v-if="lastResult.success" class="font-medium">
                {{
                  t('CAPTAIN_ROLETA.REDEEM.SUCCESS_FULL', {
                    prize: fmtPrize(lastResult),
                    name:
                      lastResult.contact_name ||
                      t('CAPTAIN_ROLETA.REDEEM.FALLBACK_CLIENT'),
                  })
                }}
              </div>
              <div v-else class="font-medium">
                {{
                  t('CAPTAIN_ROLETA.REDEEM.ERROR_FULL', {
                    message: errorText(lastResult.error_code),
                  })
                }}
              </div>
            </div>
          </div>

          <div
            class="rounded-xl border border-n-weak bg-n-alpha-black2 p-6 shadow-sm"
          >
            <div class="flex items-center justify-between mb-4">
              <h2 class="text-lg font-semibold text-n-slate-12">
                {{ t('CAPTAIN_ROLETA.HISTORY.TITLE') }}
              </h2>
              <Button
                variant="ghost"
                icon="i-lucide-refresh-cw"
                size="xs"
                :is-loading="loadingPending"
                @click="loadPending"
              />
            </div>

            <div v-if="loadingPending" class="text-sm text-n-slate-11 py-3">
              {{ t('CAPTAIN_ROLETA.HISTORY.LOADING') }}
            </div>
            <div
              v-else-if="pending.length === 0"
              class="text-sm text-n-slate-11 py-3"
            >
              {{ t('CAPTAIN_ROLETA.HISTORY.EMPTY') }}
            </div>
            <div v-else class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead class="text-xs text-n-slate-11 uppercase tracking-wide">
                  <tr class="border-b border-n-weak">
                    <th class="text-left py-2 px-2">
                      {{ t('CAPTAIN_ROLETA.HISTORY.COL_CODE') }}
                    </th>
                    <th class="text-left py-2 px-2">
                      {{ t('CAPTAIN_ROLETA.HISTORY.COL_PRIZE') }}
                    </th>
                    <th class="text-left py-2 px-2">
                      {{ t('CAPTAIN_ROLETA.HISTORY.COL_CLIENT') }}
                    </th>
                    <th class="text-left py-2 px-2">
                      {{ t('CAPTAIN_ROLETA.HISTORY.COL_GENERATED') }}
                    </th>
                    <th class="text-left py-2 px-2">
                      {{ t('CAPTAIN_ROLETA.HISTORY.COL_STATUS') }}
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    v-for="row in pending"
                    :key="row.code"
                    class="border-b border-n-weak last:border-b-0"
                  >
                    <td class="py-2 px-2 font-mono font-bold text-n-slate-12">
                      {{ row.code }}
                    </td>
                    <td class="py-2 px-2">{{ fmtPrize(row) }}</td>
                    <td class="py-2 px-2 text-n-slate-11">
                      {{ row.contact_name || row.contact_phone || '—' }}
                    </td>
                    <td class="py-2 px-2 text-n-slate-11">
                      {{ fmtDateTime(row.revealed_at) }}
                    </td>
                    <td class="py-2 px-2">
                      <span
                        v-if="row.redeemed_at"
                        class="inline-flex items-center gap-1 text-n-teal-11 text-xs"
                      >
                        {{ t('CAPTAIN_ROLETA.HISTORY.STATUS_REDEEMED_PREFIX') }}
                        {{ fmtDateTime(row.redeemed_at) }}
                      </span>
                      <span
                        v-else
                        class="inline-flex items-center gap-1 text-n-amber-11 text-xs"
                      >
                        {{ t('CAPTAIN_ROLETA.HISTORY.STATUS_PENDING') }}
                      </span>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </template>

        <template v-if="tab === 'relatorio'">
          <div
            class="rounded-xl border border-n-weak bg-n-alpha-black2 p-6 shadow-sm"
          >
            <div class="flex items-center justify-between mb-4">
              <div>
                <h2 class="text-lg font-semibold text-n-slate-12">
                  {{ t('CAPTAIN_ROLETA.REPORT.TITLE') }}
                </h2>
                <p class="text-sm text-n-slate-11">
                  {{ t('CAPTAIN_ROLETA.REPORT.DESC') }}
                </p>
              </div>
              <div class="flex items-center gap-2">
                <select
                  v-model.number="reportPeriod"
                  class="rounded-md border border-n-weak bg-transparent text-sm px-2 py-1"
                  @change="loadReport"
                >
                  <option :value="7">
                    {{ t('CAPTAIN_ROLETA.REPORT.PERIOD_7') }}
                  </option>
                  <option :value="14">
                    {{ t('CAPTAIN_ROLETA.REPORT.PERIOD_14') }}
                  </option>
                  <option :value="30">
                    {{ t('CAPTAIN_ROLETA.REPORT.PERIOD_30') }}
                  </option>
                </select>
                <Button
                  variant="ghost"
                  icon="i-lucide-refresh-cw"
                  size="xs"
                  :is-loading="loadingReport"
                  @click="loadReport"
                />
              </div>
            </div>

            <div v-if="loadingReport" class="text-sm text-n-slate-11 py-3">
              {{ t('CAPTAIN_ROLETA.REPORT.LOADING') }}
            </div>
            <div
              v-else-if="!report || report.by_receptionist.length === 0"
              class="text-sm text-n-slate-11 py-3"
            >
              {{ t('CAPTAIN_ROLETA.REPORT.EMPTY') }}
            </div>
            <div v-else>
              <div class="grid grid-cols-2 md:grid-cols-4 gap-3 mb-5">
                <div
                  class="rounded-lg border border-n-weak bg-n-alpha-black1 p-3"
                >
                  <div class="text-xs text-n-slate-11 uppercase tracking-wide">
                    {{ t('CAPTAIN_ROLETA.REPORT.KPI_TOTAL') }}
                  </div>
                  <div class="text-2xl font-semibold text-n-slate-12 mt-1">
                    {{ report.team_total }}
                  </div>
                </div>
                <div
                  class="rounded-lg border border-n-weak bg-n-alpha-black1 p-3"
                >
                  <div class="text-xs text-n-slate-11 uppercase tracking-wide">
                    {{ t('CAPTAIN_ROLETA.REPORT.KPI_AVG') }}
                  </div>
                  <div class="text-2xl font-semibold text-n-slate-12 mt-1">
                    {{ report.team_avg }}
                  </div>
                </div>
                <div
                  class="rounded-lg border border-n-weak bg-n-alpha-black1 p-3"
                >
                  <div class="text-xs text-n-slate-11 uppercase tracking-wide">
                    {{ t('CAPTAIN_ROLETA.REPORT.KPI_COUNT') }}
                  </div>
                  <div class="text-2xl font-semibold text-n-slate-12 mt-1">
                    {{ report.receptionist_count }}
                  </div>
                </div>
                <div
                  class="rounded-lg border border-n-amber-7 bg-n-amber-3 p-3"
                  :class="{
                    'border-n-weak bg-n-alpha-black1':
                      report.anomaly_threshold === 0,
                  }"
                >
                  <div
                    class="text-xs uppercase tracking-wide"
                    :class="
                      report.anomaly_threshold
                        ? 'text-n-amber-11'
                        : 'text-n-slate-11'
                    "
                  >
                    {{ t('CAPTAIN_ROLETA.REPORT.KPI_THRESHOLD') }}
                  </div>
                  <div
                    class="text-2xl font-semibold mt-1"
                    :class="
                      report.anomaly_threshold
                        ? 'text-n-amber-12'
                        : 'text-n-slate-12'
                    "
                  >
                    {{ t('CAPTAIN_ROLETA.REPORT.KPI_THRESHOLD_PREFIX')
                    }}{{ report.anomaly_threshold }}
                  </div>
                </div>
              </div>

              <div class="overflow-x-auto">
                <table class="w-full text-sm">
                  <thead
                    class="text-xs text-n-slate-11 uppercase tracking-wide"
                  >
                    <tr class="border-b border-n-weak">
                      <th class="text-left py-2 px-2">
                        {{ t('CAPTAIN_ROLETA.REPORT.COL_RECEPTIONIST') }}
                      </th>
                      <th class="text-right py-2 px-2">
                        {{ t('CAPTAIN_ROLETA.REPORT.COL_TOTAL') }}
                      </th>
                      <th class="text-right py-2 px-2">
                        {{ t('CAPTAIN_ROLETA.REPORT.COL_BRINDES') }}
                      </th>
                      <th class="text-right py-2 px-2">
                        {{ t('CAPTAIN_ROLETA.REPORT.COL_DESCONTOS') }}
                      </th>
                      <th class="text-right py-2 px-2">
                        {{ t('CAPTAIN_ROLETA.REPORT.COL_SUM_DISCOUNT') }}
                      </th>
                      <th class="text-left py-2 px-2">
                        {{ t('CAPTAIN_ROLETA.REPORT.COL_STATUS') }}
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr
                      v-for="r in report.by_receptionist"
                      :key="r.receptionist_user_id"
                      :class="
                        'border-b border-n-weak last:border-b-0 ' +
                        (r.anomaly ? 'bg-n-amber-2' : '')
                      "
                    >
                      <td class="py-2 px-2">
                        <div class="font-medium text-n-slate-12">
                          {{ r.receptionist_name }}
                        </div>
                        <div
                          v-if="r.receptionist_email"
                          class="text-xs text-n-slate-11"
                        >
                          {{ r.receptionist_email }}
                        </div>
                      </td>
                      <td class="py-2 px-2 text-right font-semibold">
                        {{ r.total_redemptions }}
                      </td>
                      <td class="py-2 px-2 text-right text-n-slate-11">
                        {{ r.brinde_count }}
                      </td>
                      <td class="py-2 px-2 text-right text-n-slate-11">
                        {{ r.desconto_count }}
                      </td>
                      <td class="py-2 px-2 text-right text-n-slate-11">
                        {{ fmtCurrency(r.total_discount_value) }}%
                      </td>
                      <td class="py-2 px-2">
                        <span
                          v-if="r.anomaly"
                          class="inline-flex items-center gap-1 text-xs px-2 py-1 rounded-full bg-n-amber-4 text-n-amber-12 font-medium"
                        >
                          {{ t('CAPTAIN_ROLETA.REPORT.STATUS_ANOMALY') }}
                        </span>
                        <span v-else class="text-xs text-n-slate-11">
                          {{ t('CAPTAIN_ROLETA.REPORT.STATUS_NORMAL') }}
                        </span>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>

              <p class="text-xs text-n-slate-11 mt-4">
                {{
                  t('CAPTAIN_ROLETA.REPORT.FOOTER_HINT').replace(
                    '{threshold}',
                    report.anomaly_threshold
                  )
                }}
              </p>
            </div>
          </div>
        </template>
      </div>
    </template>
  </PageLayout>
</template>
