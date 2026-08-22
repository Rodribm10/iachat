<script setup>
import { useAlert } from 'dashboard/composables';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { computed, ref, watch } from 'vue';
import { useStoreGetters } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const getters = useStoreGetters();
const { uiSettings, updateUISettings } = useUISettings();

const inboxes = computed(() => getters['inboxes/getInboxes'].value || []);

// Modelo: ui_settings.aggressive_alert_inbox_ids
//   undefined / null → todas as inboxes (default histórico)
//   []               → desligado pra esse usuário
//   [id, id, ...]    → apenas essas inboxes
const enabled = ref(true);
const selectedInboxIds = ref([]);
const applyToAll = ref(true);

const initFromSettings = settings => {
  const raw = settings?.aggressive_alert_inbox_ids;
  if (Array.isArray(raw)) {
    if (raw.length === 0) {
      enabled.value = false;
      applyToAll.value = true;
      selectedInboxIds.value = [];
    } else {
      enabled.value = true;
      applyToAll.value = false;
      selectedInboxIds.value = raw.map(id => Number(id));
    }
  } else {
    enabled.value = true;
    applyToAll.value = true;
    selectedInboxIds.value = [];
  }
};

watch(
  uiSettings,
  value => {
    initFromSettings(value);
  },
  { immediate: true }
);

const persist = async () => {
  let value;
  if (!enabled.value) {
    value = [];
  } else if (applyToAll.value) {
    value = null;
  } else {
    value = selectedInboxIds.value.map(id => Number(id));
  }
  try {
    await updateUISettings({ aggressive_alert_inbox_ids: value });
    useAlert(t('PROFILE_SETTINGS.FORM.API.UPDATE_SUCCESS'));
  } catch (e) {
    useAlert(t('PROFILE_SETTINGS.FORM.API.UPDATE_ERROR'));
  }
};

const handleEnabledChange = event => {
  enabled.value = event.target.checked;
  persist();
};

const handleApplyToAllChange = event => {
  applyToAll.value = event.target.checked;
  if (applyToAll.value) {
    selectedInboxIds.value = [];
  }
  persist();
};

const handleInboxToggle = inboxId => {
  const id = Number(inboxId);
  if (selectedInboxIds.value.includes(id)) {
    selectedInboxIds.value = selectedInboxIds.value.filter(i => i !== id);
  } else {
    selectedInboxIds.value = [...selectedInboxIds.value, id];
  }
  persist();
};

const isInboxSelected = inboxId =>
  selectedInboxIds.value.includes(Number(inboxId));
</script>

<template>
  <div class="aggressive-alert-settings flex flex-col gap-4">
    <p class="description">
      {{
        $t(
          'PROFILE_SETTINGS.FORM.AGGRESSIVE_ALERT_SECTION.DESCRIPTION',
          'Banner vermelho que aparece quando uma conversa fica sem resposta há 5+ minutos. Útil pra não perder cliente, mas pode ser intrusivo se você não atende todas as inboxes.'
        )
      }}
    </p>

    <label class="toggle-row">
      <input
        type="checkbox"
        :checked="enabled"
        class="toggle-input"
        @change="handleEnabledChange"
      />
      <span class="toggle-label">
        {{
          $t(
            'PROFILE_SETTINGS.FORM.AGGRESSIVE_ALERT_SECTION.ENABLED',
            'Ativar alerta de conversa parada'
          )
        }}
      </span>
    </label>

    <div v-if="enabled" class="scope-section">
      <label class="toggle-row">
        <input
          type="checkbox"
          :checked="applyToAll"
          class="toggle-input"
          @change="handleApplyToAllChange"
        />
        <span class="toggle-label">
          {{
            $t(
              'PROFILE_SETTINGS.FORM.AGGRESSIVE_ALERT_SECTION.APPLY_TO_ALL',
              'Aplicar em todas as caixas de entrada'
            )
          }}
        </span>
      </label>

      <div v-if="!applyToAll" class="inbox-list">
        <p class="hint">
          {{
            $t(
              'PROFILE_SETTINGS.FORM.AGGRESSIVE_ALERT_SECTION.INBOX_HINT',
              'Selecione as caixas onde você quer receber o alerta:'
            )
          }}
        </p>
        <label v-for="inbox in inboxes" :key="inbox.id" class="inbox-row">
          <input
            type="checkbox"
            :checked="isInboxSelected(inbox.id)"
            class="toggle-input"
            @change="handleInboxToggle(inbox.id)"
          />
          <span>{{ inbox.name }}</span>
        </label>
        <p v-if="!inboxes.length" class="empty">
          {{
            $t(
              'PROFILE_SETTINGS.FORM.AGGRESSIVE_ALERT_SECTION.NO_INBOXES',
              'Nenhuma caixa de entrada cadastrada.'
            )
          }}
        </p>
      </div>
    </div>
  </div>
</template>

<style lang="scss" scoped>
.aggressive-alert-settings {
  max-width: 480px;
}

.description {
  @apply text-n-slate-11;
  font-size: 13px;
  line-height: 1.5;
  margin: 0;
}

.toggle-row {
  display: flex;
  align-items: center;
  gap: 8px;
  cursor: pointer;
  user-select: none;
}

.toggle-input {
  cursor: pointer;
}

.toggle-label {
  font-size: 14px;
  font-weight: 500;
}

.scope-section {
  margin-left: 24px;
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.inbox-list {
  margin-left: 24px;
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding-top: 4px;
}

.inbox-row {
  display: flex;
  align-items: center;
  gap: 8px;
  cursor: pointer;
  font-size: 13px;
}

.hint {
  font-size: 12px;
  @apply text-n-slate-11;
  margin: 0;
}

.empty {
  font-size: 12px;
  @apply text-n-slate-11;
  font-style: italic;
}
</style>
