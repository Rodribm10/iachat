<script setup>
import { reactive, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required, minLength } from '@vuelidate/validators';
import { useMapGetter } from 'dashboard/composables/store';

import Input from 'dashboard/components-next/input/Input.vue';
import Editor from 'dashboard/components-next/Editor/Editor.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

const props = defineProps({
  mode: {
    type: String,
    required: true,
    validator: value => ['edit', 'create'].includes(value),
  },
  response: {
    type: Object,
    default: () => ({}),
  },
  assistants: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['submit', 'cancel']);
const { t } = useI18n();

const formState = {
  uiFlags: useMapGetter('captainResponses/getUIFlags'),
};

const initialState = {
  question: '',
  answer: '',
  assistant_id: '',
};

const state = reactive({ ...initialState });

const validationRules = computed(() => {
  const rules = {
    question: { required, minLength: minLength(1) },
    answer: { required, minLength: minLength(1) },
  };

  if (props.assistants && props.assistants.length > 0) {
    rules.assistant_id = { required };
  }

  return rules;
});

const v$ = useVuelidate(validationRules, state);

const isLoading = computed(() => formState.uiFlags.value.creatingItem);

const getErrorMessage = (field, errorKey) => {
  return v$.value[field].$error
    ? t(`CAPTAIN.RESPONSES.FORM.${errorKey}.ERROR`)
    : '';
};

const formErrors = computed(() => ({
  question: getErrorMessage('question', 'QUESTION'),
  answer: getErrorMessage('answer', 'ANSWER'),
  assistant_id: v$.value.assistant_id?.$error
    ? t(
        'CAPTAIN.RESPONSES.FORM.ASSISTANT.ERROR',
        'Por favor, selecione um assistente.'
      )
    : '',
}));

const handleCancel = () => emit('cancel');

const prepareDocumentDetails = () => ({
  question: state.question,
  answer: state.answer,
  ...(state.assistant_id ? { assistant_id: state.assistant_id } : {}),
});

const handleSubmit = async () => {
  const isFormValid = await v$.value.$validate();
  if (!isFormValid) {
    return;
  }

  emit('submit', prepareDocumentDetails());
};

const updateStateFromResponse = response => {
  if (!response) return;

  const { question, answer, assistant_id } = response;

  Object.assign(state, {
    question,
    answer,
    assistant_id: assistant_id || '',
  });
};

watch(
  () => props.response,
  newResponse => {
    if (newResponse) {
      updateStateFromResponse(newResponse);
    }
  },
  { immediate: true }
);
</script>

<template>
  <form class="flex flex-col gap-4" @submit.prevent="handleSubmit">
    <Input
      v-model="state.question"
      :label="t('CAPTAIN.RESPONSES.FORM.QUESTION.LABEL')"
      :placeholder="t('CAPTAIN.RESPONSES.FORM.QUESTION.PLACEHOLDER')"
      :message="formErrors.question"
      :message-type="formErrors.question ? 'error' : 'info'"
    />
    <Editor
      v-model="state.answer"
      :label="t('CAPTAIN.RESPONSES.FORM.ANSWER.LABEL')"
      :placeholder="t('CAPTAIN.RESPONSES.FORM.ANSWER.PLACEHOLDER')"
      :message="formErrors.answer"
      :max-length="10000"
      :message-type="formErrors.answer ? 'error' : 'info'"
    />
    <div
      v-if="assistants && assistants.length > 0"
      class="flex flex-col w-full gap-2"
    >
      <label class="text-sm font-medium text-n-slate-11">
        {{ t('CAPTAIN.RESPONSES.FORM.ASSISTANT.LABEL', 'Assistente') }}
      </label>
      <ComboBox
        v-model="state.assistant_id"
        :options="assistants"
        :has-error="!!formErrors.assistant_id"
        :message="formErrors.assistant_id"
        :placeholder="
          t(
            'CAPTAIN.RESPONSES.FORM.ASSISTANT.PLACEHOLDER',
            'Por favor selecione o Assistente'
          )
        "
      />
    </div>
    <div class="flex items-center justify-between w-full gap-3 mt-2">
      <Button
        type="button"
        variant="faded"
        color="slate"
        :label="t('CAPTAIN.FORM.CANCEL')"
        class="w-full bg-n-alpha-2 text-n-blue-11 hover:bg-n-alpha-3"
        @click="handleCancel"
      />
      <Button
        type="submit"
        :label="t(`CAPTAIN.FORM.${mode.toUpperCase()}`)"
        class="w-full"
        :is-loading="isLoading"
        :disabled="isLoading"
      />
    </div>
  </form>
</template>
