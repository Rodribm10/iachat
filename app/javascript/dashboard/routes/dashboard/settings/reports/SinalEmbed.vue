<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';

// O Sinal roda como app próprio (sinal.innova1001.com.br) com banco e jobs de
// IA que o Chatwoot não tem; o embed é a única forma de trazer as páginas
// idênticas sem duplicar o pipeline de dados. O cookie de sessão do Sinal é
// SameSite=None + Partitioned, então o login feito dentro do iframe persiste.
const SINAL_BASE_URL =
  window.chatwootConfig?.sinalBaseUrl || 'https://sinal.innova1001.com.br';

const route = useRoute();
const { t } = useI18n();

const src = computed(() => `${SINAL_BASE_URL}${route.meta.sinalPath || '/'}`);
const title = computed(() => t(route.meta.sinalLabelKey || 'SIDEBAR.REPORTS'));
</script>

<template>
  <div class="flex flex-col w-full h-full min-h-0 bg-n-background">
    <div
      class="flex items-center justify-between px-4 py-2 border-b border-n-weak shrink-0"
    >
      <span class="text-sm font-medium text-n-slate-12">{{ title }}</span>
      <a
        :href="src"
        target="_blank"
        rel="noopener noreferrer"
        class="text-xs text-n-blue-11 hover:underline"
      >
        {{ $t('SINAL_REPORTS.OPEN_IN_SINAL') }}
      </a>
    </div>
    <iframe
      :src="src"
      :title="title"
      class="flex-1 w-full border-0"
      allow="clipboard-write"
    />
  </div>
</template>
