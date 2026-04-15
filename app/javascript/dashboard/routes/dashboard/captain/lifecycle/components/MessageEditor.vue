<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { AVAILABLE_VARIABLES } from '../constants';

const props = defineProps({
  modelValue: { type: String, default: '' },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();

const textareaRef = ref(null);
const showAutocomplete = ref(false);
const autocompleteFilter = ref('');

const filteredVariables = computed(() => {
  const q = autocompleteFilter.value.toLowerCase();
  if (!q) return AVAILABLE_VARIABLES;
  return AVAILABLE_VARIABLES.filter(v => v.key.toLowerCase().includes(q));
});

const onInput = e => {
  const val = e.target.value;
  emit('update:modelValue', val);

  const caret = e.target.selectionStart;
  const before = val.slice(0, caret);
  const match = before.match(/\{\{\s*([a-zA-Z0-9_.]*)$/);
  if (match) {
    showAutocomplete.value = true;
    autocompleteFilter.value = match[1];
  } else {
    showAutocomplete.value = false;
  }
};

const insertVariable = key => {
  const ta = textareaRef.value;
  if (!ta) return;
  const val = props.modelValue;
  const caret = ta.selectionStart;
  const before = val.slice(0, caret).replace(/\{\{\s*[a-zA-Z0-9_.]*$/, '');
  const after = val.slice(caret);
  const inserted = `{{ ${key} }}`;
  emit('update:modelValue', before + inserted + after);
  showAutocomplete.value = false;
};
</script>

<template>
  <div class="relative">
    <textarea
      ref="textareaRef"
      :value="modelValue"
      rows="6"
      class="w-full border rounded p-2 font-mono text-sm"
      :placeholder="t('CAPTAIN_LIFECYCLE.RULES.WIZARD.FIELDS.MESSAGE_BODY')"
      @input="onInput"
    />

    <div
      v-if="showAutocomplete && filteredVariables.length"
      class="absolute z-20 mt-1 bg-n-solid-1 border border-n-slate-4 rounded shadow-lg max-h-60 overflow-auto w-80"
    >
      <button
        v-for="v in filteredVariables"
        :key="v.key"
        type="button"
        class="w-full text-left px-3 py-2 hover:bg-n-alpha-2 text-xs"
        @click="insertVariable(v.key)"
      >
        <span class="font-mono">{{ v.key }}</span>
        <span class="block text-n-slate-11">{{ v.descKey }}</span>
      </button>
    </div>
  </div>
</template>
