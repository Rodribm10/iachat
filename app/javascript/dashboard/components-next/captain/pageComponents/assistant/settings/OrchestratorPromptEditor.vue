<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  assistant: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['submit']);

// Delimitador que separa o prompt base do sistema das instruções do assistente.
// Este comentário fica na string salva no banco, mas é invisível para o usuário na UI.
const SECTION_DELIMITER = '\n# ---SECAO-ASSISTENTE---\n';

const { t } = useI18n();

const systemText = ref('');
const assistantText = ref('');
const originalSystem = ref('');
const originalAssistant = ref('');
// true quando o prompt salvo não tem delimitador — avisa o usuário antes de salvar
const missingDelimiter = ref(false);

function splitPrompt(fullText) {
  const idx = fullText.indexOf(SECTION_DELIMITER);
  if (idx === -1) {
    missingDelimiter.value = true;
    return { system: fullText, assistant: '' };
  }
  missingDelimiter.value = false;
  return {
    system: fullText.substring(0, idx),
    assistant: fullText.substring(idx + SECTION_DELIMITER.length),
  };
}

function joinPrompt() {
  return systemText.value + SECTION_DELIMITER + assistantText.value;
}

const isDirty = computed(
  () =>
    systemText.value !== originalSystem.value ||
    assistantText.value !== originalAssistant.value
);

const updateStateFromAssistant = assistant => {
  const fullText =
    assistant.orchestrator_prompt ||
    assistant.default_orchestrator_prompt ||
    '';
  const { system, assistant: assistantPart } = splitPrompt(fullText);
  systemText.value = system;
  assistantText.value = assistantPart;
  originalSystem.value = system;
  originalAssistant.value = assistantPart;
};

watch(
  () => props.assistant,
  newAssistant => {
    if (newAssistant) updateStateFromAssistant(newAssistant);
  },
  { immediate: true }
);

const handleSave = () => {
  const full = joinPrompt();
  if (!full.trim()) {
    useAlert(t('CAPTAIN.ASSISTANTS.ORCHESTRATOR_PROMPT.VALIDATION_ERROR'));
    return;
  }
  emit('submit', { orchestrator_prompt: full });
  originalSystem.value = systemText.value;
  originalAssistant.value = assistantText.value;
};

const handleReset = () => {
  emit('submit', { orchestrator_prompt: null });
  const defaultFull = props.assistant?.default_orchestrator_prompt || '';
  const { system, assistant: assistantPart } = splitPrompt(defaultFull);
  systemText.value = system;
  assistantText.value = assistantPart;
  originalSystem.value = system;
  originalAssistant.value = assistantPart;
};
</script>

<template>
  <div class="flex flex-col gap-6 w-full">
    <!-- Aviso de risco -->
    <div
      class="flex items-start gap-3 p-3 rounded-lg bg-yellow-50 border border-yellow-200 text-yellow-800 w-full"
    >
      <span class="i-lucide-triangle-alert mt-0.5 shrink-0 text-yellow-500" />
      <p class="text-sm leading-relaxed">
        {{ t('CAPTAIN.ASSISTANTS.ORCHESTRATOR_PROMPT.WARNING') }}
      </p>
    </div>

    <!-- Aviso: prompt sem delimitador (versão antiga) -->
    <div
      v-if="missingDelimiter"
      class="flex items-start gap-3 p-3 rounded-lg bg-blue-50 border border-blue-200 text-blue-800 w-full"
    >
      <span class="i-lucide-info mt-0.5 shrink-0 text-blue-500" />
      <p class="text-sm leading-relaxed">
        {{ t('CAPTAIN_ORCHESTRATOR_EDITOR.MISSING_DELIMITER_PREFIX') }}
        <strong>{{
          t('CAPTAIN_ORCHESTRATOR_EDITOR.MISSING_DELIMITER_BUTTON')
        }}</strong>
        {{ t('CAPTAIN_ORCHESTRATOR_EDITOR.MISSING_DELIMITER_SUFFIX') }}
      </p>
    </div>

    <!-- Seção 1: Prompt Base do Sistema -->
    <div class="flex flex-col gap-2 w-full">
      <div class="flex items-center gap-2">
        <span class="i-lucide-shield text-n-slate-10 text-sm" />
        <div class="flex flex-col">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('CAPTAIN.ASSISTANTS.ORCHESTRATOR_PROMPT.SYSTEM_LABEL') }}
          </label>
          <p class="text-xs text-n-slate-11">
            {{ t('CAPTAIN.ASSISTANTS.ORCHESTRATOR_PROMPT.SYSTEM_DESCRIPTION') }}
          </p>
        </div>
      </div>
      <textarea
        v-model="systemText"
        :placeholder="
          t('CAPTAIN.ASSISTANTS.ORCHESTRATOR_PROMPT.SYSTEM_PLACEHOLDER')
        "
        class="w-full min-h-[500px] rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2.5 text-sm text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:ring-2 focus:ring-n-brand resize-y font-mono"
      />
    </div>

    <!-- Divisor visual -->
    <div class="flex items-center gap-3">
      <div class="flex-1 border-t border-dashed border-n-weak" />
      <span class="text-xs text-n-slate-9 whitespace-nowrap">
        {{ t('CAPTAIN.ASSISTANTS.ORCHESTRATOR_PROMPT.DIVIDER_LABEL') }}
      </span>
      <div class="flex-1 border-t border-dashed border-n-weak" />
    </div>

    <!-- Seção 2: Instruções do Assistente -->
    <div class="flex flex-col gap-2 w-full">
      <div class="flex items-center gap-2">
        <span class="i-lucide-pencil text-n-brand text-sm" />
        <div class="flex flex-col">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('CAPTAIN.ASSISTANTS.ORCHESTRATOR_PROMPT.ASSISTANT_LABEL') }}
          </label>
          <p class="text-xs text-n-slate-11">
            {{
              t('CAPTAIN.ASSISTANTS.ORCHESTRATOR_PROMPT.ASSISTANT_DESCRIPTION')
            }}
          </p>
        </div>
      </div>
      <textarea
        v-model="assistantText"
        :placeholder="
          t('CAPTAIN.ASSISTANTS.ORCHESTRATOR_PROMPT.ASSISTANT_PLACEHOLDER')
        "
        class="w-full min-h-[500px] rounded-lg border border-n-brand/30 bg-n-alpha-1 px-3 py-2.5 text-sm text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:ring-2 focus:ring-n-brand resize-y font-mono"
      />
    </div>

    <!-- Botões -->
    <div class="flex items-center gap-3 mt-2 w-full">
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
