<script>
import { useVuelidate } from '@vuelidate/core';
import JasmineAPI from 'dashboard/api/inbox/jasmine';
import { useAlert } from 'dashboard/composables';
import JasmineKnowledgeBase from './components/JasmineKnowledgeBase.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { computed, onMounted } from 'vue';

export default {
  components: {
    JasmineKnowledgeBase,
    ComboBox,
    NextButton,
  },
  props: {
    inbox: {
      type: Object,
      required: true,
    },
    showKnowledgeBase: {
      type: Boolean,
      default: true,
    },
    isTab: {
      type: Boolean,
      default: false,
    },
  },
  setup() {
    const store = useStore();
    const units = useMapGetter('captainUnits/getUnits');

    const unitList = computed(() => {
      return units.value.map(unit => ({
        value: unit.id,
        label: unit.name,
      }));
    });

    onMounted(() => {
      store.dispatch('captainUnits/get');
    });

    return { v$: useVuelidate(), unitList };
  },
  data() {
    return {
      isEnabled: false,
      systemPrompt: '',
      captainUnitId: null,
      typingDelay: 0,
      isUpdating: false,
    };
  },
  mounted() {
    this.fetchSettings();
  },
  methods: {
    async fetchSettings() {
      try {
        const { data } = await JasmineAPI.getSettings(this.inbox.id);
        this.isEnabled = data.is_enabled;
        this.systemPrompt = data.system_prompt || '';
        this.captainUnitId =
          data.captain_unit_id || this.inbox.captain_unit_id || null;
      } catch (error) {
        // Fallback to inbox-linked unit when jasmine config endpoint is unavailable.
        this.captainUnitId = this.inbox.captain_unit_id || null;
      }
      this.typingDelay = this.inbox.typing_delay || 0;
    },
    async updateSettings() {
      this.isUpdating = true;
      try {
        // Persist unit link in the inbox config so it works even if Jasmine API is unavailable.
        await this.$store.dispatch('inboxes/updateInbox', {
          id: this.inbox.id,
          formData: false,
          captain_unit_id: this.captainUnitId,
          typing_delay: this.typingDelay,
        });

        // Best effort: persist Jasmine-specific settings when backend endpoint exists.
        try {
          await JasmineAPI.updateSettings(this.inbox.id, {
            inbox_config: {
              is_enabled: this.isEnabled,
              system_prompt: this.systemPrompt,
              captain_unit_id: this.captainUnitId,
            },
          });
        } catch (error) {
          // Ignore missing/unavailable jasmine endpoint to avoid blocking unit link save.
        }

        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (error) {
        useAlert(error.message || this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      } finally {
        this.isUpdating = false;
      }
    },
  },
};
</script>

<template>
  <div :class="{ 'mx-8': !isTab }">
    <div class="settings-section">
      <div class="flex flex-col gap-1 items-start mb-4">
        <h2 class="text-xl font-medium text-slate-900 dark:text-slate-100">
          {{ $t('JASMINE.CONFIG.TITLE') }}
        </h2>
        <p class="text-sm text-slate-600 dark:text-slate-400">
          {{ $t('JASMINE.CONFIG.DESCRIPTION') }}
        </p>
      </div>

      <div class="mb-6">
        <label class="flex items-center gap-2 cursor-pointer">
          <input
            v-model="isEnabled"
            type="checkbox"
            class="form-checkbox h-5 w-5 text-woot-500 rounded border-gray-300 focus:ring-woot-500"
          />
          <span class="text-sm font-medium text-slate-700 dark:text-slate-200">
            {{ $t('JASMINE.CONFIG.ENABLE') }}
          </span>
        </label>
      </div>

      <div class="mb-6">
        <label
          class="block text-sm font-medium text-slate-700 dark:text-slate-200 mb-2"
        >
          {{ $t('JASMINE.CONFIG.SYSTEM_PROMPT') }}
        </label>
        <textarea
          v-model="systemPrompt"
          rows="6"
          class="w-full text-sm rounded-md border-gray-300 dark:border-slate-700 dark:bg-slate-900 focus:border-woot-500 focus:ring-woot-500"
          :placeholder="$t('JASMINE.CONFIG.SYSTEM_PROMPT_HELP')"
        />
        <p class="mt-1 text-xs text-slate-500">
          {{ $t('JASMINE.CONFIG.SYSTEM_PROMPT_HELP') }}
        </p>
      </div>

      <div class="mb-6">
        <label
          class="block text-sm font-medium text-slate-700 dark:text-slate-200 mb-2"
        >
          {{
            $t('CAPTAIN_SETTINGS.UNITS.INBOX.CONNECT_UNIT_LABEL') ||
            'Captain Unit'
          }}
        </label>
        <ComboBox
          id="captainUnit"
          v-model="captainUnitId"
          :options="unitList"
          :placeholder="
            $t('CAPTAIN_SETTINGS.UNITS.INBOX.CONNECT_UNIT_PLACEHOLDER') ||
            'Select a unit'
          "
          class="[&>div>button]:bg-white dark:[&>div>button]:bg-slate-900 [&>div>button:not(.focused)]:dark:outline-n-weak [&>div>button:not(.focused)]:hover:!outline-n-slate-6"
        />
        <p class="mt-1 text-xs text-slate-500">
          {{
            $t('CAPTAIN_SETTINGS.UNITS.INBOX.CONNECT_UNIT_HELP') ||
            'Selecione uma Unidade Pix.'
          }}
        </p>
      </div>

      <div class="mb-6">
        <label
          class="block text-sm font-medium text-slate-700 dark:text-slate-200 mb-2"
        >
          {{
            $t('JASMINE.CONFIG.TYPING_DELAY_LABEL') ||
            'Buffer / Delay de Digitação (Segundos)'
          }}
        </label>
        <input
          v-model.number="typingDelay"
          type="number"
          min="0"
          max="60"
          class="w-full text-sm rounded-md border-gray-300 dark:border-slate-700 dark:bg-slate-900 focus:border-woot-500 focus:ring-woot-500"
          :placeholder="
            $t('JASMINE.CONFIG.TYPING_DELAY_PLACEHOLDER') || 'Ex: 5'
          "
        />
        <p class="mt-1 text-xs text-slate-500">
          {{
            $t('JASMINE.CONFIG.TYPING_DELAY_HELP') ||
            'O tempo que a IA aguardará mensagens (Buffer) antes de simular a digitação e responder. Zero para imediato.'
          }}
        </p>
      </div>

      <NextButton
        :is-loading="isUpdating"
        :label="$t('JASMINE.CONFIG.UPDATE_BUTTON')"
        @click="updateSettings"
      />

      <JasmineKnowledgeBase v-if="showKnowledgeBase" :inbox-id="inbox.id" />
    </div>
  </div>
</template>
