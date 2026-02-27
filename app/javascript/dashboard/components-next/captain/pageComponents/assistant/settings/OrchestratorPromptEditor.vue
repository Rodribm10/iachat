<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  assistant: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['submit']);

const { t } = useI18n();

const promptText = ref('');
const originalText = ref('');
const isDirty = ref(false);

const updateStateFromAssistant = assistant => {
  // Pré-popula com o prompt customizado salvo, ou com o .liquid padrão como ponto de partida
  const initialValue =
    assistant.orchestrator_prompt ||
    assistant.default_orchestrator_prompt ||
    '';
  promptText.value = initialValue;
  originalText.value = initialValue;
  isDirty.value = false;
};

watch(
  () => props.assistant,
  newAssistant => {
    if (newAssistant) updateStateFromAssistant(newAssistant);
  },
  { immediate: true }
);

watch(promptText, newVal => {
  isDirty.value = newVal !== originalText.value;
});

const handleSave = () => {
  if (!promptText.value.trim()) {
    useAlert(t('CAPTAIN.ASSISTANTS.ORCHESTRATOR_PROMPT.VALIDATION_ERROR'));
    return;
  }
  emit('submit', { orchestrator_prompt: promptText.value });
  originalText.value = promptText.value;
  isDirty.value = false;
};

const handleReset = () => {
  // Envia null para limpar o banco e voltar ao .liquid padrão
  emit('submit', { orchestrator_prompt: null });
  // Restaura a textarea para mostrar o conteúdo padrão novamente
  const defaultPrompt = props.assistant?.default_orchestrator_prompt || '';
  promptText.value = defaultPrompt;
  originalText.value = defaultPrompt;
  isDirty.value = false;
};
</script>

<template>
  <div class="flex flex-col gap-4">
    <!-- Aviso de risco -->
    <div
      class="flex items-start gap-3 p-3 rounded-lg bg-yellow-50 border border-yellow-200 text-yellow-800"
    >
      <span class="i-lucide-triangle-alert mt-0.5 shrink-0 text-yellow-500" />
      <p class="text-sm leading-relaxed">
        {{ t('CAPTAIN.ASSISTANTS.ORCHESTRATOR_PROMPT.WARNING') }}
      </p>
    </div>

    <!-- Textarea do prompt -->
    <div class="flex flex-col gap-1.5">
      <label class="text-sm font-medium text-n-slate-12">
        {{ t('CAPTAIN.ASSISTANTS.ORCHESTRATOR_PROMPT.LABEL') }}
      </label>
      <p class="text-xs text-n-slate-11">
        {{ t('CAPTAIN.ASSISTANTS.ORCHESTRATOR_PROMPT.DESCRIPTION') }}
      </p>
      <textarea
        v-model="promptText"
        rows="18"
        :placeholder="t('CAPTAIN.ASSISTANTS.ORCHESTRATOR_PROMPT.PLACEHOLDER')"
        class="w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2.5 text-sm text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:ring-2 focus:ring-n-brand resize-y font-mono"
      />
    </div>

    <!-- Botões -->
    <div class="flex items-center gap-3">
      <button
        class="inline-flex items-center gap-1.5 rounded-lg bg-n-brand px-4 py-2 text-sm font-medium text-white hover:bg-n-brand-dark transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
        :disabled="!isDirty"
        @click="handleSave"
      >
        <span class="i-lucide-save" />
        {{ t('CAPTAIN.ASSISTANTS.ORCHESTRATOR_PROMPT.SAVE_BUTTON') }}
      </button>

      <button
        class="inline-flex items-center gap-1.5 rounded-lg border border-n-weak px-4 py-2 text-sm font-medium text-n-slate-11 hover:bg-n-alpha-2 transition-colors"
        @click="handleReset"
      >
        <span class="i-lucide-rotate-ccw" />
        {{ t('CAPTAIN.ASSISTANTS.ORCHESTRATOR_PROMPT.RESET_BUTTON') }}
      </button>

      <p
        v-if="!props.assistant?.orchestrator_prompt"
        class="text-xs text-n-slate-10 italic ml-auto"
      >
        {{ t('CAPTAIN.ASSISTANTS.ORCHESTRATOR_PROMPT.USING_DEFAULT') }}
      </p>
      <p v-else class="text-xs text-n-brand italic ml-auto">
        {{ t('CAPTAIN.ASSISTANTS.ORCHESTRATOR_PROMPT.USING_CUSTOM') }}
      </p>
    </div>
  </div>
</template>
