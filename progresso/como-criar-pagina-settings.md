# Como Criar uma Nova Página de Settings no Chatwoot

**Data:** 2026-02-22

## Objetivo

Criar uma nova tela na área de Configurações do dashboard do Chatwoot (ex: `/settings/captain/units`).

## Contexto

O Chatwoot usa **Vue 3 com Composition API** (`<script setup>`). Telas de settings antigas usavam Options API e `woot-button`, mas o padrão atual usa componentes do `dashboard/components-next`. Usar o padrão antigo causa **tela em branco** (crash silencioso).

---

## Passo a Passo

### 1. Criar o arquivo Vue da página

Local padrão: `app/javascript/dashboard/routes/dashboard/settings/<area>/<NomeDaPagina>.vue`

**Template mínimo funcional:**

```vue
<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const { t } = useI18n();
const router = useRouter();
const store = useStore();

// Exemplo: getter de uma store Vuex namespaced
const records = useMapGetter('minhaStore/getRecords');
const uiFlags = useMapGetter('minhaStore/getUIFlags');

const deleteDialogRef = ref(null);
const itemToDelete = ref(null);

onMounted(async () => {
  await store.dispatch('minhaStore/get');
});
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.isFetching"
    :loading-message="t('MINHA_SECAO.LOADING')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="t('MINHA_SECAO.TITLE')"
        :description="t('MINHA_SECAO.DESC')"
      >
        <template #actions>
          <Button
            :label="t('MINHA_SECAO.ADD')"
            icon="i-lucide-plus"
            @click="goToNew"
          />
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <div class="flex flex-col px-6 pb-8">
        <!-- conteúdo aqui -->

        <!-- Para modal de confirmação de exclusão -->
        <Dialog
          ref="deleteDialogRef"
          type="alert"
          :title="t('MINHA_SECAO.DELETE.TITLE')"
          :description="t('MINHA_SECAO.DELETE.MESSAGE')"
          :confirm-button-label="t('MINHA_SECAO.DELETE.YES')"
          @confirm="confirmDelete"
        />
      </div>
    </template>
  </SettingsLayout>
</template>
```

> ⚠️ **CRÍTICO:** O `Dialog` de confirmação deve ficar **dentro** do slot `#body`, nunca fora do `<SettingsLayout>`. Dois root elements causam tela branca no Vue 3.

---

### 2. Registrar a rota

Arquivo: `app/javascript/dashboard/routes/dashboard/settings/<area>/<area>.routes.js`

```js
import MinhaNovaPage from './MinhaNovaPage.vue';

// Dentro de children:
{
  path: 'minha-rota',
  name: 'minha_rota_name',
  component: MinhaNovaPage,
  meta: { permissions: ['administrator'] },
},
```

---

### 3. Adicionar item no Sidebar

Arquivo: `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`

Dentro do grupo correto (ex: Captain), adicione:

```js
{
  name: 'Minha Página',
  label: t('SIDEBAR.MINHA_CHAVE'),
  activeOn: ['minha_rota_name'],
  to: accountScopedRoute('minha_rota_name'),
},
```

---

### 4. Adicionar traduções

**Sidebar key** → `app/javascript/dashboard/i18n/locale/pt_BR/settings.json`:
```json
"SIDEBAR": {
  "MINHA_CHAVE": "Minha Página"
}
```

**Textos da página** → Criar ou editar o arquivo específico da feature em `i18n/locale/pt_BR/`:
```json
{
  "MINHA_SECAO": {
    "TITLE": "...",
    "DESC": "...",
    "ADD": "Adicionar",
    "DELETE": {
      "TITLE": "Confirmar exclusão",
      "MESSAGE": "Tem certeza?",
      "YES": "Excluir"
    }
  }
}
```

---

### 5. Criar ou registrar a Vuex Store (se necessário)

Arquivo: `app/javascript/dashboard/store/modules/minhaStore.js`

```js
export const state = {
  records: [],
  uiFlags: { isFetching: false, isDeleting: false },
};

export const getters = {
  getRecords: $state => $state.records,
  getUIFlags: $state => $state.uiFlags,
};

// ... actions e mutations

export default {
  namespaced: true,
  state, getters, actions, mutations,
};
```

Registrar em `app/javascript/dashboard/store/index.js`:
```js
import minhaStore from './modules/minhaStore';
// dentro de modules:
minhaStore,
```

---

## Componentes Disponíveis (components-next)

| Componente | Import |
|---|---|
| `Button` | `dashboard/components-next/button/Button.vue` |
| `Dialog` | `dashboard/components-next/dialog/Dialog.vue` |
| `Input` | `dashboard/components-next/input/Input.vue` |
| `TextArea` | `dashboard/components-next/textarea/TextArea.vue` |
| `Icon` | `dashboard/components-next/icon/Icon.vue` |

Ícones usam o prefixo `i-lucide-*` (ex: `i-lucide-plus`, `i-lucide-trash-2`, `i-lucide-pencil`).

---

## Exemplo real

Ver `app/javascript/dashboard/routes/dashboard/settings/captain/units/Index.vue` — tela de Unidades Pix implementada com sucesso seguindo este padrão.
