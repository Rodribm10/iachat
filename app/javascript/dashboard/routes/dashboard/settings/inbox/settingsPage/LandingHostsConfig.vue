<script>
/* eslint-disable @intlify/vue-i18n/no-raw-text */
import landingHostsApi from 'dashboard/api/landingHosts';
import { useAlert } from 'dashboard/composables';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { mapGetters } from 'vuex';

export default {
  name: 'LandingHostsConfig',
  components: { NextButton },
  props: {
    inbox: {
      type: Object,
      required: true,
    },
  },
  data() {
    return {
      landingHosts: [],
      newHostname: '',
      newUnitCode: '',
      isLoading: false,
      isSaving: false,
      labels: {
        title: 'Landing Pages (Tracking de Origem)',
        subtitle:
          'Defina os domínios de Landing Pages que enviam leads para esta caixa de entrada. O sistema usará esses domínios para identificar automaticamente a origem de cada conversa.',
        loading: 'Carregando...',
        empty: 'Nenhum domínio cadastrado ainda.',
        colHostname: 'Hostname',
        colCode: 'Código / Unidade',
        remove: 'Remover',
        addTitle: 'Adicionar Domínio',
        labelHostname: 'Hostname *',
        placeholderHostname: 'express.seuhotel.com.br',
        labelCode: 'Código Unidade',
        placeholderCode: 'EXPRESS',
        labelSaving: 'Salvando...',
        labelAdd: 'Adicionar',
        hint: 'Informe o domínio exato sem https://, ex: landing.meusite.com.br',
        errLoad: 'Erro ao carregar os domínios.',
        errAdd:
          'Erro ao adicionar domínio. Verifique se já existe ou o formato é válido.',
        errDel: 'Erro ao remover domínio.',
        successAdd: 'Domínio adicionado com sucesso!',
        successDel: 'Domínio removido.',
      },
    };
  },
  computed: {
    ...mapGetters({ currentAccountId: 'getCurrentAccountId' }),
    addLabel() {
      return this.isSaving ? this.labels.labelSaving : this.labels.labelAdd;
    },
  },
  mounted() {
    this.fetchHosts();
  },
  methods: {
    async fetchHosts() {
      this.isLoading = true;
      try {
        const { data } = await landingHostsApi.getHosts(
          this.currentAccountId,
          this.inbox.id
        );
        this.landingHosts = data;
      } catch {
        useAlert(this.labels.errLoad);
      } finally {
        this.isLoading = false;
      }
    },
    async addHost() {
      if (!this.newHostname.trim()) return;
      this.isSaving = true;

      // Sanitiza: remove protocolo, www, barras e espaços
      const cleanHostname = this.newHostname
        .trim()
        .toLowerCase()
        .replace(/^https?:\/\//i, '')
        .replace(/^www\./, '')
        .replace(/\/.*$/, '');

      try {
        const { data } = await landingHostsApi.createHost(
          this.currentAccountId,
          this.inbox.id,
          {
            hostname: cleanHostname,
            unit_code: this.newUnitCode.trim().toUpperCase(),
          }
        );
        this.landingHosts.push(data);
        this.newHostname = '';
        this.newUnitCode = '';
        useAlert(this.labels.successAdd);
      } catch {
        useAlert(this.labels.errAdd);
      } finally {
        this.isSaving = false;
      }
    },
    async deleteHost(id) {
      try {
        await landingHostsApi.deleteHost(
          this.currentAccountId,
          this.inbox.id,
          id
        );
        this.landingHosts = this.landingHosts.filter(h => h.id !== id);
        useAlert(this.labels.successDel);
      } catch {
        useAlert(this.labels.errDel);
      }
    },
  },
};
</script>

<template>
  <div class="mx-8 mt-4 pb-12">
    <div class="mb-6">
      <h2 class="text-base font-semibold text-n-slate-12 mb-1">
        {{ labels.title }}
      </h2>
      <p class="text-sm text-n-slate-11">
        {{ labels.subtitle }}
      </p>
    </div>

    <!-- Lista de hosts cadastrados -->
    <div class="mb-6 border border-n-slate-3 rounded-lg overflow-hidden">
      <div
        v-if="isLoading"
        class="flex items-center justify-center py-8 text-sm text-n-slate-11"
      >
        {{ labels.loading }}
      </div>
      <div
        v-else-if="landingHosts.length === 0"
        class="py-8 text-center text-sm text-n-slate-11"
      >
        {{ labels.empty }}
      </div>
      <table v-else class="w-full text-sm">
        <thead class="bg-n-slate-2 text-n-slate-11 uppercase text-xs">
          <tr>
            <th class="text-left px-4 py-3 font-medium">
              {{ labels.colHostname }}
            </th>
            <th class="text-left px-4 py-3 font-medium">
              {{ labels.colCode }}
            </th>
            <th class="px-4 py-3 text-right" />
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="host in landingHosts"
            :key="host.id"
            class="border-t border-n-slate-3 hover:bg-n-slate-1"
          >
            <td class="px-4 py-3 font-mono text-n-slate-12 text-xs">
              {{ host.hostname }}
            </td>
            <td class="px-4 py-3 text-n-slate-11">
              {{ host.unit_code || '—' }}
            </td>
            <td class="px-4 py-3 text-right">
              <button
                class="text-xs text-ruby-9 hover:text-ruby-11 font-medium transition-colors"
                @click="deleteHost(host.id)"
              >
                {{ labels.remove }}
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Formulário de adição -->
    <div class="border border-n-slate-3 rounded-lg p-4 bg-n-slate-1">
      <h3 class="text-sm font-semibold text-n-slate-12 mb-3">
        {{ labels.addTitle }}
      </h3>
      <div class="flex flex-col gap-3 sm:flex-row sm:items-end">
        <div class="flex-1">
          <label class="block text-xs font-medium text-n-slate-11 mb-1">
            {{ labels.labelHostname }}
          </label>
          <woot-input
            v-model="newHostname"
            :placeholder="labels.placeholderHostname"
            class="[&>input]:!mb-0"
            @keyup.enter="addHost"
          />
        </div>
        <div class="w-36">
          <label class="block text-xs font-medium text-n-slate-11 mb-1">
            {{ labels.labelCode }}
          </label>
          <woot-input
            v-model="newUnitCode"
            :placeholder="labels.placeholderCode"
            class="[&>input]:!mb-0"
            @keyup.enter="addHost"
          />
        </div>
        <NextButton
          :label="addLabel"
          :disabled="!newHostname.trim() || isSaving"
          class="flex-shrink-0 mb-px"
          @click="addHost"
        />
      </div>
      <p class="text-xs text-n-slate-10 mt-2">
        {{ labels.hint }}
      </p>
    </div>
  </div>
</template>
