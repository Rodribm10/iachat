<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import SettingsLayout from '../../SettingsLayout.vue';
import BaseSettingsHeader from '../../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const store = useStore();

const inboxes = useMapGetter('inboxes/getInboxes');
const templates = useMapGetter('captainNotificationTemplates/getRecords');
const uiFlags = useMapGetter('captainNotificationTemplates/getUIFlags');

const selectedInboxId = ref(null);
const editingId = ref(null);
const showNewForm = ref(false);

// ─── Inboxes com Captain assistant ────────────────────────────────────────────
const captainInboxes = computed(() =>
  (inboxes.value || []).filter(i => i.captain_assistant_id)
);

const hasInboxes = computed(() => captainInboxes.value.length > 0);

// ─── Formulários ──────────────────────────────────────────────────────────────
const emptyForm = () => ({
  label: '',
  content: '',
  timing_minutes: 10,
  timing_direction: 'before',
  active: true,
});

const newForm = ref(emptyForm());
const editForm = ref(emptyForm());

const VARIABLES = [
  '{{guest_name}}',
  '{{check_in_time}}',
  '{{check_out_time}}',
  '{{suite_name}}',
  '{{unit_name}}',
];

// ─── Carregamento ─────────────────────────────────────────────────────────────
onMounted(async () => {
  await store.dispatch('inboxes/get');
});

watch(selectedInboxId, async id => {
  if (id) {
    await store.dispatch('captainNotificationTemplates/fetch', id);
    showNewForm.value = false;
    editingId.value = null;
  }
});

// ─── Novo template ────────────────────────────────────────────────────────────
const openNewForm = () => {
  newForm.value = emptyForm();
  showNewForm.value = true;
};

const cancelNew = () => {
  showNewForm.value = false;
  newForm.value = emptyForm();
};

const saveNew = async () => {
  if (!newForm.value.label || !newForm.value.content) return;
  try {
    await store.dispatch('captainNotificationTemplates/create', {
      inboxId: selectedInboxId.value,
      payload: newForm.value,
    });
    useAlert(t('CAPTAIN_SETTINGS.NOTIFICATIONS.CREATE.SUCCESS'));
    showNewForm.value = false;
    newForm.value = emptyForm();
  } catch {
    useAlert(t('CAPTAIN_SETTINGS.NOTIFICATIONS.CREATE.ERROR'));
  }
};

// ─── Edição ───────────────────────────────────────────────────────────────────
const startEdit = template => {
  editingId.value = template.id;
  editForm.value = { ...template };
};

const cancelEdit = () => {
  editingId.value = null;
  editForm.value = emptyForm();
};

const saveEdit = async () => {
  try {
    await store.dispatch('captainNotificationTemplates/update', {
      inboxId: selectedInboxId.value,
      id: editingId.value,
      payload: editForm.value,
    });
    useAlert(t('CAPTAIN_SETTINGS.NOTIFICATIONS.UPDATE.SUCCESS'));
    editingId.value = null;
  } catch {
    useAlert(t('CAPTAIN_SETTINGS.NOTIFICATIONS.UPDATE.ERROR'));
  }
};

// ─── Toggle ativo ─────────────────────────────────────────────────────────────
const toggleActive = async template => {
  try {
    await store.dispatch('captainNotificationTemplates/update', {
      inboxId: selectedInboxId.value,
      id: template.id,
      payload: { active: !template.active },
    });
  } catch {
    useAlert(t('CAPTAIN_SETTINGS.NOTIFICATIONS.UPDATE.ERROR'));
  }
};

// ─── Exclusão ─────────────────────────────────────────────────────────────────
const deleteTemplate = async template => {
  try {
    await store.dispatch('captainNotificationTemplates/delete', {
      inboxId: selectedInboxId.value,
      id: template.id,
    });
    useAlert(t('CAPTAIN_SETTINGS.NOTIFICATIONS.DELETE.SUCCESS'));
  } catch {
    useAlert(t('CAPTAIN_SETTINGS.NOTIFICATIONS.DELETE.ERROR'));
  }
};

// ─── Variáveis ────────────────────────────────────────────────────────────────
const insertVariable = (variable, target) => {
  if (target === 'new') {
    newForm.value.content += variable;
  } else {
    editForm.value.content += variable;
  }
};

const directionLabel = direction =>
  direction === 'before'
    ? t('CAPTAIN_SETTINGS.NOTIFICATIONS.DIRECTION.BEFORE')
    : t('CAPTAIN_SETTINGS.NOTIFICATIONS.DIRECTION.AFTER');

const timingDisplay = template =>
  `${template.timing_minutes} ${t('CAPTAIN_SETTINGS.NOTIFICATIONS.FORM.MINUTES')} ${directionLabel(template.timing_direction)} ${t('CAPTAIN_SETTINGS.NOTIFICATIONS.DIRECTION.OF_ARRIVAL')}`;
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.isFetching"
    :loading-message="t('CAPTAIN_SETTINGS.NOTIFICATIONS.LOADING')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="t('CAPTAIN_SETTINGS.NOTIFICATIONS.TITLE')"
        :description="t('CAPTAIN_SETTINGS.NOTIFICATIONS.DESCRIPTION')"
      >
        <template #actions>
          <Button
            v-if="selectedInboxId && !showNewForm"
            icon="i-lucide-plus"
            :label="t('CAPTAIN_SETTINGS.NOTIFICATIONS.ADD')"
            @click="openNewForm"
          />
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <div class="flex flex-col gap-6 px-6 pb-8">
        <!-- Seletor de inbox -->
        <div class="flex flex-col gap-2">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('CAPTAIN_SETTINGS.NOTIFICATIONS.INBOX_LABEL') }}
          </label>
          <div v-if="!hasInboxes" class="text-sm text-n-slate-10">
            {{ t('CAPTAIN_SETTINGS.NOTIFICATIONS.NO_CAPTAIN_INBOXES') }}
          </div>
          <div v-else class="flex flex-wrap gap-2">
            <button
              v-for="inbox in captainInboxes"
              :key="inbox.id"
              class="flex items-center gap-2 rounded-lg border px-4 py-2 text-sm transition-colors"
              :class="
                selectedInboxId === inbox.id
                  ? 'border-w-500 bg-w-50 text-w-700 font-medium'
                  : 'border-n-weak text-n-slate-11 hover:border-n-300'
              "
              @click="selectedInboxId = inbox.id"
            >
              <span class="i-lucide-message-circle w-4 h-4" />
              {{ inbox.name }}
            </button>
          </div>
        </div>

        <!-- Conteúdo: só aparece após selecionar inbox -->
        <div v-if="selectedInboxId" class="flex flex-col gap-3">
          <!-- Template list -->
          <div
            v-for="template in templates"
            :key="template.id"
            class="rounded-lg border border-n-75 bg-white p-4"
          >
            <!-- View mode -->
            <div
              v-if="editingId !== template.id"
              class="flex items-start justify-between gap-3"
            >
              <div class="flex flex-col gap-1 flex-1 min-w-0">
                <span class="text-sm font-semibold text-n-slate-12">{{
                  template.label
                }}</span>
                <span class="text-sm text-n-slate-11 whitespace-pre-line">{{
                  template.content
                }}</span>
                <span class="text-xs text-n-slate-10 mt-1">
                  {{ timingDisplay(template) }}
                </span>
              </div>
              <div class="flex items-center gap-2 shrink-0">
                <button
                  class="text-xs px-2 py-1 rounded"
                  :class="
                    template.active
                      ? 'bg-n-teal-2 text-n-teal-11'
                      : 'bg-n-slate-3 text-n-slate-11'
                  "
                  @click="toggleActive(template)"
                >
                  {{
                    template.active
                      ? t('CAPTAIN_SETTINGS.NOTIFICATIONS.ACTIVE')
                      : t('CAPTAIN_SETTINGS.NOTIFICATIONS.INACTIVE')
                  }}
                </button>
                <button
                  class="text-n-slate-10 hover:text-n-slate-12"
                  @click="startEdit(template)"
                >
                  <span class="i-lucide-pencil w-4 h-4" />
                </button>
                <button
                  class="text-n-ruby-9 hover:text-n-ruby-11"
                  @click="deleteTemplate(template)"
                >
                  <span class="i-lucide-trash-2 w-4 h-4" />
                </button>
              </div>
            </div>

            <!-- Edit mode -->
            <div v-else class="flex flex-col gap-3">
              <input
                v-model="editForm.label"
                :placeholder="
                  t('CAPTAIN_SETTINGS.NOTIFICATIONS.FORM.LABEL_PLACEHOLDER')
                "
                class="w-full rounded border border-n-weak px-3 py-2 text-sm focus:outline-none focus:border-w-500"
              />
              <textarea
                v-model="editForm.content"
                :placeholder="
                  t('CAPTAIN_SETTINGS.NOTIFICATIONS.FORM.CONTENT_PLACEHOLDER')
                "
                rows="3"
                class="w-full rounded border border-n-weak px-3 py-2 text-sm focus:outline-none focus:border-w-500 resize-none"
              />
              <!-- Variable chips -->
              <div class="flex flex-wrap gap-1">
                <button
                  v-for="v in VARIABLES"
                  :key="v"
                  class="text-xs bg-n-slate-3 text-n-slate-11 px-2 py-0.5 rounded hover:bg-n-slate-4"
                  @click="insertVariable(v, 'edit')"
                >
                  {{ v }}
                </button>
              </div>
              <!-- Timing row -->
              <div class="flex items-center gap-2 text-sm flex-wrap">
                <span class="text-n-slate-11">{{
                  t('CAPTAIN_SETTINGS.NOTIFICATIONS.FORM.SEND')
                }}</span>
                <input
                  v-model.number="editForm.timing_minutes"
                  type="number"
                  min="1"
                  class="w-16 rounded border border-n-weak px-2 py-1 text-sm text-center focus:outline-none focus:border-w-500"
                />
                <span class="text-n-slate-11">{{
                  t('CAPTAIN_SETTINGS.NOTIFICATIONS.FORM.MINUTES')
                }}</span>
                <select
                  v-model="editForm.timing_direction"
                  class="rounded border border-n-weak px-2 py-1 text-sm focus:outline-none focus:border-w-500"
                >
                  <option value="before">
                    {{ t('CAPTAIN_SETTINGS.NOTIFICATIONS.DIRECTION.BEFORE') }}
                  </option>
                  <option value="after">
                    {{ t('CAPTAIN_SETTINGS.NOTIFICATIONS.DIRECTION.AFTER') }}
                  </option>
                </select>
                <span class="text-n-slate-11">{{
                  t('CAPTAIN_SETTINGS.NOTIFICATIONS.DIRECTION.OF_ARRIVAL')
                }}</span>
              </div>
              <div class="flex gap-2 justify-end">
                <Button
                  variant="clear"
                  :label="t('CAPTAIN_SETTINGS.NOTIFICATIONS.FORM.CANCEL')"
                  @click="cancelEdit"
                />
                <Button
                  :label="t('CAPTAIN_SETTINGS.NOTIFICATIONS.FORM.SAVE')"
                  :is-loading="uiFlags.isSaving"
                  @click="saveEdit"
                />
              </div>
            </div>
          </div>

          <!-- New form -->
          <div
            v-if="showNewForm"
            class="rounded-lg border border-w-300 bg-w-25 p-4 flex flex-col gap-3"
          >
            <input
              v-model="newForm.label"
              :placeholder="
                t('CAPTAIN_SETTINGS.NOTIFICATIONS.FORM.LABEL_PLACEHOLDER')
              "
              class="w-full rounded border border-n-weak px-3 py-2 text-sm focus:outline-none focus:border-w-500"
            />
            <textarea
              v-model="newForm.content"
              :placeholder="
                t('CAPTAIN_SETTINGS.NOTIFICATIONS.FORM.CONTENT_PLACEHOLDER')
              "
              rows="3"
              class="w-full rounded border border-n-weak px-3 py-2 text-sm focus:outline-none focus:border-w-500 resize-none"
            />
            <!-- Variable chips -->
            <div class="flex flex-wrap gap-1">
              <button
                v-for="v in VARIABLES"
                :key="v"
                class="text-xs bg-n-slate-3 text-n-slate-11 px-2 py-0.5 rounded hover:bg-n-slate-4"
                @click="insertVariable(v, 'new')"
              >
                {{ v }}
              </button>
            </div>
            <!-- Timing row -->
            <div class="flex items-center gap-2 text-sm flex-wrap">
              <span class="text-n-slate-11">{{
                t('CAPTAIN_SETTINGS.NOTIFICATIONS.FORM.SEND')
              }}</span>
              <input
                v-model.number="newForm.timing_minutes"
                type="number"
                min="1"
                class="w-16 rounded border border-n-weak px-2 py-1 text-sm text-center focus:outline-none focus:border-w-500"
              />
              <span class="text-n-slate-11">{{
                t('CAPTAIN_SETTINGS.NOTIFICATIONS.FORM.MINUTES')
              }}</span>
              <select
                v-model="newForm.timing_direction"
                class="rounded border border-n-weak px-2 py-1 text-sm focus:outline-none focus:border-w-500"
              >
                <option value="before">
                  {{ t('CAPTAIN_SETTINGS.NOTIFICATIONS.DIRECTION.BEFORE') }}
                </option>
                <option value="after">
                  {{ t('CAPTAIN_SETTINGS.NOTIFICATIONS.DIRECTION.AFTER') }}
                </option>
              </select>
              <span class="text-n-slate-11">{{
                t('CAPTAIN_SETTINGS.NOTIFICATIONS.DIRECTION.OF_ARRIVAL')
              }}</span>
            </div>
            <div class="flex gap-2 justify-end">
              <Button
                variant="clear"
                :label="t('CAPTAIN_SETTINGS.NOTIFICATIONS.FORM.CANCEL')"
                @click="cancelNew"
              />
              <Button
                :label="t('CAPTAIN_SETTINGS.NOTIFICATIONS.FORM.SAVE')"
                :is-loading="uiFlags.isSaving"
                @click="saveNew"
              />
            </div>
          </div>

          <!-- Empty state (sem templates, sem form aberto) -->
          <div
            v-if="!templates.length && !showNewForm"
            class="flex flex-col items-center justify-center gap-4 py-16 text-center"
          >
            <div
              class="size-14 rounded-full bg-n-slate-3 flex items-center justify-center"
            >
              <span class="i-lucide-bell w-6 h-6 text-n-slate-10" />
            </div>
            <div class="flex flex-col gap-1">
              <p class="mb-0 text-base font-medium text-n-slate-12">
                {{ t('CAPTAIN_SETTINGS.NOTIFICATIONS.EMPTY.TITLE') }}
              </p>
              <p class="mb-0 max-w-sm text-sm text-n-slate-10">
                {{ t('CAPTAIN_SETTINGS.NOTIFICATIONS.EMPTY.DESC') }}
              </p>
            </div>
            <Button
              icon="i-lucide-plus"
              :label="t('CAPTAIN_SETTINGS.NOTIFICATIONS.ADD')"
              @click="openNewForm"
            />
          </div>
        </div>

        <!-- Estado inicial: nenhuma inbox selecionada -->
        <div
          v-else-if="hasInboxes"
          class="flex flex-col items-center justify-center gap-3 py-16 text-center"
        >
          <span class="i-lucide-mouse-pointer-click w-8 h-8 text-n-slate-9" />
          <p class="mb-0 text-sm text-n-slate-10">
            {{ t('CAPTAIN_SETTINGS.NOTIFICATIONS.SELECT_INBOX_HINT') }}
          </p>
        </div>
      </div>
    </template>
  </SettingsLayout>
</template>
