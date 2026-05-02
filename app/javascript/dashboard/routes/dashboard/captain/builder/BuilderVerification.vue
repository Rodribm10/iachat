<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import hermesBuilderApi from 'dashboard/api/captain/hermesBuilder';

const { t } = useI18n();

const assistants = ref([]);
const selectedSlug = ref('');
const checks = ref([]);
const summary = ref(null);
const loading = ref(false);
const repairing = ref({});

const groupedChecks = computed(() => {
  const groups = {};
  checks.value.forEach(c => {
    const cat = c.category || 'outros';
    if (!groups[cat]) groups[cat] = [];
    groups[cat].push(c);
  });
  return groups;
});

const categoryLabel = cat => {
  const map = {
    db: 'CAPTAIN_HERMES_BUILDER.VERIFY.CATEGORY_DB',
    pricing: 'CAPTAIN_HERMES_BUILDER.VERIFY.CATEGORY_PRICING',
    routing: 'CAPTAIN_HERMES_BUILDER.VERIFY.CATEGORY_ROUTING',
    humanization: 'CAPTAIN_HERMES_BUILDER.VERIFY.CATEGORY_HUMANIZATION',
    mcp: 'CAPTAIN_HERMES_BUILDER.VERIFY.CATEGORY_MCP',
  };
  return t(map[cat] || 'CAPTAIN_HERMES_BUILDER.VERIFY.CATEGORY_OTHER');
};

const fetchAssistants = async () => {
  try {
    const { data } = await hermesBuilderApi.fetchAssistants();
    assistants.value = data.assistants || [];
    if (assistants.value.length && !selectedSlug.value) {
      selectedSlug.value = assistants.value[0].slug;
    }
  } catch (e) {
    useAlert(
      t('CAPTAIN_HERMES_BUILDER.VERIFY.FETCH_FAILED', {
        message: e.message || 'unknown',
      })
    );
  }
};

const runValidation = async () => {
  if (!selectedSlug.value || loading.value) return;
  loading.value = true;
  checks.value = [];
  summary.value = null;
  try {
    const { data } = await hermesBuilderApi.validate(selectedSlug.value);
    checks.value = data.results || [];
    summary.value = data;
  } catch (e) {
    useAlert(
      t('CAPTAIN_HERMES_BUILDER.VERIFY.VALIDATE_FAILED', {
        message: e.response?.data?.error || e.message || 'unknown',
      })
    );
  } finally {
    loading.value = false;
  }
};

const runRepair = async check => {
  if (!check.repair_id) return;
  repairing.value[check.repair_id] = true;
  try {
    const { data } = await hermesBuilderApi.repair(
      selectedSlug.value,
      check.repair_id
    );
    if (data.ok) {
      useAlert(
        t('CAPTAIN_HERMES_BUILDER.VERIFY.REPAIR_OK', {
          message: data.message || 'OK',
        })
      );
      await runValidation();
    } else {
      useAlert(
        t('CAPTAIN_HERMES_BUILDER.VERIFY.REPAIR_FAILED', {
          message: data.error || 'unknown',
        })
      );
    }
  } catch (e) {
    useAlert(
      t('CAPTAIN_HERMES_BUILDER.VERIFY.REPAIR_FAILED', {
        message: e.response?.data?.error || e.message || 'unknown',
      })
    );
  } finally {
    repairing.value[check.repair_id] = false;
  }
};

const statusIcon = status => {
  if (status === 'PASS') return '✓';
  if (status === 'FAIL') return '✗';
  if (status === 'WARN') return '⚠';
  return '?';
};

const statusClass = status => {
  if (status === 'PASS') return 'badge--pass';
  if (status === 'FAIL') return 'badge--fail';
  if (status === 'WARN') return 'badge--warn';
  return 'badge--unknown';
};

onMounted(() => {
  fetchAssistants();
});
</script>

<template>
  <div class="verification-wrapper">
    <header class="verification-header">
      <h2>{{ t('CAPTAIN_HERMES_BUILDER.VERIFY.TITLE') }}</h2>
      <p>{{ t('CAPTAIN_HERMES_BUILDER.VERIFY.DESCRIPTION') }}</p>
    </header>

    <div class="controls">
      <select
        v-model="selectedSlug"
        class="select"
        :disabled="!assistants.length || loading"
      >
        <option v-if="!assistants.length" value="">
          {{ t('CAPTAIN_HERMES_BUILDER.VERIFY.NO_ASSISTANTS') }}
        </option>
        <option v-for="a in assistants" :key="a.id" :value="a.slug">
          {{ a.name }} — {{ a.slug }}
        </option>
      </select>
      <Button
        variant="primary"
        :disabled="!selectedSlug || loading"
        @click="runValidation"
      >
        {{
          loading
            ? t('CAPTAIN_HERMES_BUILDER.VERIFY.RUNNING')
            : t('CAPTAIN_HERMES_BUILDER.VERIFY.RUN')
        }}
      </Button>
    </div>

    <div v-if="summary" class="summary">
      <span class="summary__item summary__item--pass">
        {{ summary.pass }} {{ t('CAPTAIN_HERMES_BUILDER.VERIFY.OK_LABEL') }}
      </span>
      <span v-if="summary.fail" class="summary__item summary__item--fail">
        {{ summary.fail }}
        {{ t('CAPTAIN_HERMES_BUILDER.VERIFY.FAILS_LABEL') }}
      </span>
      <span v-if="summary.warn" class="summary__item summary__item--warn">
        {{ summary.warn }} {{ t('CAPTAIN_HERMES_BUILDER.VERIFY.WARN_LABEL') }}
      </span>
      <span class="summary__total">
        {{
          t('CAPTAIN_HERMES_BUILDER.VERIFY.OF_TOTAL', { total: summary.total })
        }}
      </span>
      <span v-if="summary.ok" class="summary__verdict summary__verdict--pass">
        ✅ {{ t('CAPTAIN_HERMES_BUILDER.VERIFY.VERDICT_PASS') }}
      </span>
      <span v-else class="summary__verdict summary__verdict--fail">
        ❌ {{ t('CAPTAIN_HERMES_BUILDER.VERIFY.VERDICT_FAIL') }}
      </span>
    </div>

    <section v-if="checks.length" class="checks-section">
      <div v-for="(items, cat) in groupedChecks" :key="cat" class="check-group">
        <h3 class="check-group__title">
          {{ categoryLabel(cat) }}
        </h3>
        <ul class="check-list">
          <li
            v-for="(check, idx) in items"
            :key="idx"
            class="check-item"
            :class="`check-item--${check.status.toLowerCase()}`"
          >
            <span class="check-item__badge" :class="statusClass(check.status)">
              {{ statusIcon(check.status) }}
            </span>
            <div class="check-item__body">
              <div class="check-item__label">{{ check.label }}</div>
              <div v-if="check.detail" class="check-item__detail">
                {{ check.detail }}
              </div>
            </div>
            <button
              v-if="
                check.repair_id &&
                (check.status === 'FAIL' || check.status === 'WARN')
              "
              type="button"
              class="repair-btn"
              :disabled="repairing[check.repair_id]"
              @click="runRepair(check)"
            >
              {{
                repairing[check.repair_id]
                  ? t('CAPTAIN_HERMES_BUILDER.VERIFY.REPAIRING')
                  : t('CAPTAIN_HERMES_BUILDER.VERIFY.REPAIR')
              }}
            </button>
          </li>
        </ul>
      </div>
    </section>

    <p v-else-if="!loading && summary" class="empty-state">
      {{ t('CAPTAIN_HERMES_BUILDER.VERIFY.EMPTY_RESULTS') }}
    </p>
    <p v-else-if="!loading" class="empty-state">
      {{ t('CAPTAIN_HERMES_BUILDER.VERIFY.EMPTY') }}
    </p>
  </div>
</template>

<style scoped lang="scss">
.verification-wrapper {
  display: flex;
  flex-direction: column;
  gap: 16px;
  max-width: 1000px;
  margin: 0 auto;
  height: calc(100vh - 260px);
  overflow-y: auto;
  padding-right: 8px;
}

.verification-header {
  padding: 16px 20px;
  background: var(--color-background-light, #f7f8fa);
  border-radius: 12px;

  h2 {
    margin: 0 0 4px;
    font-size: 18px;
    font-weight: 600;
  }

  p {
    margin: 0;
    color: var(--color-text-light, #6b7280);
    font-size: 13px;
    line-height: 1.5;
  }
}

.controls {
  display: flex;
  gap: 12px;
  align-items: center;

  .select {
    flex: 1;
    padding: 10px 12px;
    border-radius: 8px;
    border: 1px solid var(--color-border, #e5e7eb);
    background: var(--color-background, #fff);
    font-size: 14px;
    outline: none;

    &:focus {
      border-color: var(--color-woot-500, #1f93ff);
    }
  }
}

.summary {
  display: flex;
  gap: 16px;
  align-items: center;
  padding: 12px 16px;
  background: var(--color-background, #fff);
  border-radius: 8px;
  border: 1px solid var(--color-border, #e5e7eb);
  font-size: 13px;
  flex-wrap: wrap;

  &__item {
    font-weight: 600;

    &--pass {
      color: #16a34a;
    }
    &--fail {
      color: #dc2626;
    }
    &--warn {
      color: #d97706;
    }
  }

  &__total {
    color: var(--color-text-light, #6b7280);
  }

  &__verdict {
    margin-left: auto;
    font-weight: 600;

    &--pass {
      color: #16a34a;
    }
    &--fail {
      color: #dc2626;
    }
  }
}

.checks-section {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.check-group {
  background: var(--color-background, #fff);
  border: 1px solid var(--color-border, #e5e7eb);
  border-radius: 12px;
  padding: 12px 16px;

  &__title {
    margin: 0 0 8px;
    font-size: 13px;
    font-weight: 600;
    color: var(--color-text-light, #6b7280);
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }
}

.check-list {
  list-style: none;
  padding: 0;
  margin: 0;
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.check-item {
  display: flex;
  align-items: flex-start;
  gap: 10px;
  padding: 8px 4px;
  border-radius: 6px;
  font-size: 13px;

  &--fail {
    background: #fef2f2;
  }
  &--warn {
    background: #fffbeb;
  }
}

.check-item__badge {
  flex-shrink: 0;
  width: 22px;
  height: 22px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: 700;
  font-size: 12px;
  color: #fff;

  &.badge--pass {
    background: #16a34a;
  }
  &.badge--fail {
    background: #dc2626;
  }
  &.badge--warn {
    background: #d97706;
  }
}

.check-item__body {
  flex: 1;
  min-width: 0;
}

.check-item__label {
  font-weight: 500;
}

.check-item__detail {
  margin-top: 2px;
  color: var(--color-text-light, #6b7280);
  font-size: 12px;
  word-break: break-word;
}

.repair-btn {
  flex-shrink: 0;
  padding: 6px 12px;
  border-radius: 6px;
  border: 1px solid var(--color-woot-500, #1f93ff);
  background: var(--color-background, #fff);
  color: var(--color-woot-500, #1f93ff);
  font-size: 12px;
  font-weight: 500;
  cursor: pointer;
  transition: all 0.15s;

  &:hover:not(:disabled) {
    background: var(--color-woot-500, #1f93ff);
    color: #fff;
  }

  &:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
}

.empty-state {
  text-align: center;
  color: var(--color-text-light, #9ca3af);
  font-size: 14px;
  padding: 32px;
  margin: 0;
}
</style>
