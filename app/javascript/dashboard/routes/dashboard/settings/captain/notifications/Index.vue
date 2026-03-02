<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import SettingsLayout from '../../SettingsLayout.vue';
import BaseSettingsHeader from '../../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const route = useRoute();
const store = useStore();

const unitId = computed(() => route.params.unitId);

const templates = useMapGetter('captainNotificationTemplates/getTemplates');
const uiFlags = useMapGetter('captainNotificationTemplates/getUIFlags');

const editingId = ref(null);
const showNewForm = ref(false);

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

onMounted(async () => {
  if (unitId.value) {
    await store.dispatch('captainNotificationTemplates/fetch', unitId.value);
  }
});

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
      unitId: unitId.value,
      ...newForm.value,
    });
    useAlert(t('CAPTAIN_SETTINGS.NOTIFICATIONS.CREATE.SUCCESS'));
    showNewForm.value = false;
    newForm.value = emptyForm();
  } catch {
    useAlert(t('CAPTAIN_SETTINGS.NOTIFICATIONS.CREATE.ERROR'));
  }
};

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
      unitId: unitId.value,
      id: editingId.value,
      ...editForm.value,
    });
    useAlert(t('CAPTAIN_SETTINGS.NOTIFICATIONS.UPDATE.SUCCESS'));
    editingId.value = null;
  } catch {
    useAlert(t('CAPTAIN_SETTINGS.NOTIFICATIONS.UPDATE.ERROR'));
  }
};

const toggleActive = async template => {
  try {
    await store.dispatch('captainNotificationTemplates/update', {
      unitId: unitId.value,
      id: template.id,
      active: !template.active,
    });
  } catch {
    useAlert(t('CAPTAIN_SETTINGS.NOTIFICATIONS.UPDATE.ERROR'));
  }
};

const deleteTemplate = async template => {
  try {
    await store.dispatch('captainNotificationTemplates/delete', {
      unitId: unitId.value,
      id: template.id,
    });
    useAlert(t('CAPTAIN_SETTINGS.NOTIFICATIONS.DELETE.SUCCESS'));
  } catch {
    useAlert(t('CAPTAIN_SETTINGS.NOTIFICATIONS.DELETE.ERROR'));
  }
};

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
      />
    </template>

    <template #body>
      <div class="flex flex-col gap-3">
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
              <span class="text-sm font-semibold text-n-900">{{
                template.label
              }}</span>
              <span class="text-sm text-n-600 whitespace-pre-line">{{
                template.content
              }}</span>
              <span class="text-xs text-n-500 mt-1">
                {{ timingDisplay(template) }}
              </span>
            </div>
            <div class="flex items-center gap-2 shrink-0">
              <button
                class="text-xs px-2 py-1 rounded"
                :class="
                  template.active ? 'bg-g-100 text-g-700' : 'bg-n-75 text-n-500'
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
                class="text-n-500 hover:text-n-700"
                @click="startEdit(template)"
              >
                <span class="i-lucide-pencil w-4 h-4" />
              </button>
              <button
                class="text-r-500 hover:text-r-700"
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
              class="w-full rounded border border-n-200 px-3 py-2 text-sm focus:outline-none focus:border-w-500"
            />
            <textarea
              v-model="editForm.content"
              :placeholder="
                t('CAPTAIN_SETTINGS.NOTIFICATIONS.FORM.CONTENT_PLACEHOLDER')
              "
              rows="3"
              class="w-full rounded border border-n-200 px-3 py-2 text-sm focus:outline-none focus:border-w-500 resize-none"
            />
            <!-- Variable chips -->
            <div class="flex flex-wrap gap-1">
              <button
                v-for="v in VARIABLES"
                :key="v"
                class="text-xs bg-n-75 text-n-700 px-2 py-0.5 rounded hover:bg-n-100"
                @click="insertVariable(v, 'edit')"
              >
                {{ v }}
              </button>
            </div>
            <!-- Timing row -->
            <div class="flex items-center gap-2 text-sm">
              <span class="text-n-600">{{
                t('CAPTAIN_SETTINGS.NOTIFICATIONS.FORM.SEND')
              }}</span>
              <input
                v-model.number="editForm.timing_minutes"
                type="number"
                min="1"
                class="w-16 rounded border border-n-200 px-2 py-1 text-sm text-center focus:outline-none focus:border-w-500"
              />
              <span class="text-n-600">{{
                t('CAPTAIN_SETTINGS.NOTIFICATIONS.FORM.MINUTES')
              }}</span>
              <select
                v-model="editForm.timing_direction"
                class="rounded border border-n-200 px-2 py-1 text-sm focus:outline-none focus:border-w-500"
              >
                <option value="before">
                  {{ t('CAPTAIN_SETTINGS.NOTIFICATIONS.DIRECTION.BEFORE') }}
                </option>
                <option value="after">
                  {{ t('CAPTAIN_SETTINGS.NOTIFICATIONS.DIRECTION.AFTER') }}
                </option>
              </select>
              <span class="text-n-600">{{
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
                :is-loading="uiFlags.isUpdating"
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
            class="w-full rounded border border-n-200 px-3 py-2 text-sm focus:outline-none focus:border-w-500"
          />
          <textarea
            v-model="newForm.content"
            :placeholder="
              t('CAPTAIN_SETTINGS.NOTIFICATIONS.FORM.CONTENT_PLACEHOLDER')
            "
            rows="3"
            class="w-full rounded border border-n-200 px-3 py-2 text-sm focus:outline-none focus:border-w-500 resize-none"
          />
          <!-- Variable chips -->
          <div class="flex flex-wrap gap-1">
            <button
              v-for="v in VARIABLES"
              :key="v"
              class="text-xs bg-n-75 text-n-700 px-2 py-0.5 rounded hover:bg-n-100"
              @click="insertVariable(v, 'new')"
            >
              {{ v }}
            </button>
          </div>
          <!-- Timing row -->
          <div class="flex items-center gap-2 text-sm">
            <span class="text-n-600">{{
              t('CAPTAIN_SETTINGS.NOTIFICATIONS.FORM.SEND')
            }}</span>
            <input
              v-model.number="newForm.timing_minutes"
              type="number"
              min="1"
              class="w-16 rounded border border-n-200 px-2 py-1 text-sm text-center focus:outline-none focus:border-w-500"
            />
            <span class="text-n-600">{{
              t('CAPTAIN_SETTINGS.NOTIFICATIONS.FORM.MINUTES')
            }}</span>
            <select
              v-model="newForm.timing_direction"
              class="rounded border border-n-200 px-2 py-1 text-sm focus:outline-none focus:border-w-500"
            >
              <option value="before">
                {{ t('CAPTAIN_SETTINGS.NOTIFICATIONS.DIRECTION.BEFORE') }}
              </option>
              <option value="after">
                {{ t('CAPTAIN_SETTINGS.NOTIFICATIONS.DIRECTION.AFTER') }}
              </option>
            </select>
            <span class="text-n-600">{{
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
              :is-loading="uiFlags.isCreating"
              @click="saveNew"
            />
          </div>
        </div>

        <!-- Add button -->
        <button
          v-if="!showNewForm"
          class="flex items-center justify-center gap-2 rounded-lg border-2 border-dashed border-n-200 py-4 text-sm text-n-500 hover:border-w-400 hover:text-w-600 transition-colors"
          @click="openNewForm"
        >
          <span class="i-lucide-plus w-4 h-4" />
          {{ t('CAPTAIN_SETTINGS.NOTIFICATIONS.ADD') }}
        </button>
      </div>
    </template>
  </SettingsLayout>
</template>
