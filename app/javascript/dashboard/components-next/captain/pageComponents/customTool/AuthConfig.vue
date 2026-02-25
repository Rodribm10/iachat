<script setup>
import { defineModel, watch, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  authType: {
    type: String,
    required: true,
    validator: value =>
      ['none', 'bearer', 'basic', 'api_key', 'custom_headers'].includes(value),
  },
});

const { t } = useI18n();

const authConfig = defineModel('authConfig', {
  type: Object,
  default: () => ({}),
});

watch(
  () => props.authType,
  () => {
    authConfig.value = {};
  }
);

// custom_headers: lista de { name, value }
const customHeaders = computed({
  get: () => authConfig.value.headers || [],
  set: val => {
    authConfig.value = { ...authConfig.value, headers: val };
  },
});

const addHeader = () => {
  customHeaders.value = [...customHeaders.value, { name: '', value: '' }];
};

const removeHeader = index => {
  customHeaders.value = customHeaders.value.filter((_, i) => i !== index);
};

const updateHeader = (index, field, val) => {
  const updated = customHeaders.value.map((h, i) =>
    i === index ? { ...h, [field]: val } : h
  );
  customHeaders.value = updated;
};
</script>

<template>
  <div class="flex flex-col gap-2">
    <!-- Bearer Token -->
    <Input
      v-if="authType === 'bearer'"
      v-model="authConfig.token"
      :label="t('CAPTAIN.CUSTOM_TOOLS.FORM.AUTH_CONFIG.BEARER_TOKEN')"
      :placeholder="
        t('CAPTAIN.CUSTOM_TOOLS.FORM.AUTH_CONFIG.BEARER_TOKEN_PLACEHOLDER')
      "
    />

    <!-- Basic Auth -->
    <template v-else-if="authType === 'basic'">
      <Input
        v-model="authConfig.username"
        :label="t('CAPTAIN.CUSTOM_TOOLS.FORM.AUTH_CONFIG.USERNAME')"
        :placeholder="
          t('CAPTAIN.CUSTOM_TOOLS.FORM.AUTH_CONFIG.USERNAME_PLACEHOLDER')
        "
      />
      <Input
        v-model="authConfig.password"
        type="password"
        :label="t('CAPTAIN.CUSTOM_TOOLS.FORM.AUTH_CONFIG.PASSWORD')"
        :placeholder="
          t('CAPTAIN.CUSTOM_TOOLS.FORM.AUTH_CONFIG.PASSWORD_PLACEHOLDER')
        "
      />
    </template>

    <!-- Single API Key -->
    <template v-else-if="authType === 'api_key'">
      <Input
        v-model="authConfig.name"
        :label="t('CAPTAIN.CUSTOM_TOOLS.FORM.AUTH_CONFIG.API_KEY')"
        :placeholder="
          t('CAPTAIN.CUSTOM_TOOLS.FORM.AUTH_CONFIG.API_KEY_PLACEHOLDER')
        "
      />
      <Input
        v-model="authConfig.key"
        :label="t('CAPTAIN.CUSTOM_TOOLS.FORM.AUTH_CONFIG.API_VALUE')"
        :placeholder="
          t('CAPTAIN.CUSTOM_TOOLS.FORM.AUTH_CONFIG.API_VALUE_PLACEHOLDER')
        "
      />
    </template>

    <!-- Custom Headers: múltiplos pares nome/valor configurados pelo usuário -->
    <template v-else-if="authType === 'custom_headers'">
      <div class="flex flex-col gap-2">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CAPTAIN.CUSTOM_TOOLS.FORM.AUTH_CONFIG.CUSTOM_HEADERS') }}
        </label>
        <p class="text-xs text-n-slate-11 -mt-1">
          {{ t('CAPTAIN.CUSTOM_TOOLS.FORM.AUTH_CONFIG.CUSTOM_HEADERS_HELP') }}
        </p>

        <div
          v-for="(header, index) in customHeaders"
          :key="index"
          class="flex gap-2 items-end"
        >
          <Input
            :model-value="header.name"
            :label="
              index === 0
                ? t('CAPTAIN.CUSTOM_TOOLS.FORM.AUTH_CONFIG.HEADER_NAME')
                : ''
            "
            :placeholder="
              t('CAPTAIN.CUSTOM_TOOLS.FORM.AUTH_CONFIG.HEADER_NAME_PLACEHOLDER')
            "
            class="flex-1 [&_input]:font-mono"
            @update:model-value="val => updateHeader(index, 'name', val)"
          />
          <Input
            :model-value="header.value"
            :label="
              index === 0
                ? t('CAPTAIN.CUSTOM_TOOLS.FORM.AUTH_CONFIG.HEADER_VALUE')
                : ''
            "
            :placeholder="
              t(
                'CAPTAIN.CUSTOM_TOOLS.FORM.AUTH_CONFIG.HEADER_VALUE_PLACEHOLDER'
              )
            "
            class="flex-1 [&_input]:font-mono"
            @update:model-value="val => updateHeader(index, 'value', val)"
          />
          <Button
            type="button"
            ghost
            sm
            slate
            icon="i-lucide-trash-2"
            class="mb-0.5 text-n-ruby-9"
            @click="removeHeader(index)"
          />
        </div>

        <Button
          type="button"
          ghost
          sm
          blue
          icon="i-lucide-plus"
          :label="t('CAPTAIN.CUSTOM_TOOLS.FORM.AUTH_CONFIG.ADD_HEADER')"
          @click="addHeader"
        />
      </div>
    </template>
  </div>
</template>
