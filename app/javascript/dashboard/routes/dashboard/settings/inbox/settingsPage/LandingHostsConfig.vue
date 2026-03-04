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
      newAutoLabel: '',
      isLoading: false,
      isSaving: false,
      isUpdating: false,
      expandedHostId: null,
      editingHostData: {},
      labels: {
        title: 'Landing Pages (Tracking de Origem)',
        subtitle:
          'Defina os domínios de Landing Pages para esta caixa de entrada e personalize a aparência de cada um.',
        loading: 'Carregando...',
        empty: 'Nenhum domínio cadastrado ainda.',
        colHostname: 'Hostname',
        colCode: 'Código / Unidade',
        colLabel: 'Etiqueta',
        colPublicLink: 'Link',
        remove: 'Remover',
        edit: 'Editar',
        open: 'Abrir',
        copy: 'Copiar',
        addTitle: 'Adicionar Domínio',
        labelHostname: 'Hostname *',
        placeholderHostname: 'express.seuhotel.com.br',
        labelCode: 'Código Unidade',
        placeholderCode: 'EXPRESS',
        labelAutoLabel: 'Etiqueta automática',
        placeholderAutoLabel: 'lead_landing_express',
        labelSaving: 'Salvando...',
        labelAdd: 'Adicionar',
        hint: 'Informe o domínio exato sem https://. Se quiser, defina uma etiqueta para aplicar automaticamente quando o lead converter.',
        errLoad: 'Erro ao carregar os domínios.',
        errAdd:
          'Erro ao adicionar domínio. Verifique se já existe ou o formato é válido.',
        errDel: 'Erro ao remover domínio.',
        successAdd: 'Domínio adicionado com sucesso!',
        successDel: 'Domínio removido.',
        successCopy: 'Link copiado!',
        errCopy: 'Não foi possível copiar o link.',

        // Novos campos
        cfgTitle: 'Editar Configurações de Aparência e Tracking',
        cfgPageTitle: 'Título Principal',
        cfgPageSubtitle: 'Subtítulo',
        cfgButtonText: 'Texto do Botão',
        cfgThemeColor: 'Cor do Botão (Ex: #25D366)',
        cfgLogoUrl: 'URL da Logo',
        cfgWhatsapp: 'Número de WhatsApp (5511999999999)',
        cfgMessage: 'Mensagem Inicial',
        cfgSource: 'Origem (UTM Source) Padrão',
        cfgCampaign: 'Campanha (UTM Campaign) Padrão',
        cfgSave: 'Salvar Alterações',
        cfgCancel: 'Cancelar',
        errUpdate: 'Erro ao salvar configurações.',
        successUpdate: 'Configurações atualizadas com sucesso!',

        // Campos Promoção
        promoSectionTitle: 'Promoções / IA (Opcional)',
        promoAdd: 'Adicionar Promoção',
        promoRemove: 'Remover',
        promoChannel: 'Canal / Origem (Ex: Instagram)',
        promoTitle: 'Ativa',
        promoName: 'Nome da Promoção',
        promoDesc: 'Descrição / Condições',
        promoCoupon: 'Cupom',
        promoValid: 'Válida Até (Data)',
        promoEmpty: 'Nenhuma promoção configurada para esta Landing Page.',
      },
    };
  },
  computed: {
    ...mapGetters({ currentAccountId: 'getCurrentAccountId' }),
    addLabel() {
      return this.isSaving ? this.labels.labelSaving : this.labels.labelAdd;
    },
    updateLabel() {
      return this.isUpdating ? this.labels.labelSaving : this.labels.cfgSave;
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
            auto_label: this.newAutoLabel.trim() || null,
          }
        );
        this.landingHosts.push(data);
        this.newHostname = '';
        this.newUnitCode = '';
        this.newAutoLabel = '';
        useAlert(this.labels.successAdd);
      } catch {
        useAlert(this.labels.errAdd);
      } finally {
        this.isSaving = false;
      }
    },
    async deleteHost(id) {
      /* eslint-disable no-alert */
      if (
        !window.confirm(
          'Deseja realmente remover este domínio? A landing page parará de funcionar imediatamente.'
        )
      ) {
        return;
      }
      /* eslint-enable no-alert */
      try {
        await landingHostsApi.deleteHost(
          this.currentAccountId,
          this.inbox.id,
          id
        );
        this.landingHosts = this.landingHosts.filter(h => h.id !== id);
        this.expandedHostId = null;
        useAlert(this.labels.successDel);
      } catch {
        useAlert(this.labels.errDel);
      }
    },
    openEdit(host) {
      this.expandedHostId = host.id;

      let promotions = [];
      if (
        host.custom_config?.promotions &&
        Array.isArray(host.custom_config.promotions)
      ) {
        promotions = [...host.custom_config.promotions];
      } else if (
        host.custom_config?.promotion &&
        host.custom_config.promotion.title
      ) {
        promotions = [{ ...host.custom_config.promotion, channel: 'Geral' }];
      }

      this.editingHostData = {
        ...host,
        custom_config: {
          ...host.custom_config,
          promotions: promotions,
        },
      };

      if (this.editingHostData.custom_config.promotion) {
        delete this.editingHostData.custom_config.promotion;
      }
    },
    cancelEdit() {
      this.expandedHostId = null;
    },
    async saveEdit() {
      this.isUpdating = true;
      try {
        const { data } = await landingHostsApi.updateHost(
          this.currentAccountId,
          this.inbox.id,
          this.expandedHostId,
          this.editingHostData
        );

        // Atualiza na lista
        const index = this.landingHosts.findIndex(h => h.id === data.id);
        if (index !== -1) {
          this.landingHosts.splice(index, 1, data);
        }

        this.expandedHostId = null;
        useAlert(this.labels.successUpdate);
      } catch {
        useAlert(this.labels.errUpdate);
      } finally {
        this.isUpdating = false;
      }
    },
    landingUrl(hostname) {
      return `https://${hostname}/lp`;
    },
    async copyLink(hostname) {
      try {
        await navigator.clipboard.writeText(this.landingUrl(hostname));
        useAlert(this.labels.successCopy);
      } catch {
        useAlert(this.labels.errCopy);
      }
    },
    addPromotion() {
      if (!this.editingHostData.custom_config.promotions) {
        this.editingHostData.custom_config.promotions = [];
      }
      this.editingHostData.custom_config.promotions.push({
        active: true,
        channel: '',
        title: '',
        description: '',
        coupon_code: '',
        valid_until: '',
      });
    },
    removePromotion(index) {
      this.editingHostData.custom_config.promotions.splice(index, 1);
    },
  },
};
</script>

<template>
  <!-- eslint-disable vue/html-closing-bracket-newline -->
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
            <th class="text-left px-4 py-3 font-medium">
              {{ labels.colLabel }}
            </th>
            <th class="text-left px-4 py-3 font-medium">
              {{ labels.colPublicLink }}
            </th>
            <th class="px-4 py-3 text-right" />
          </tr>
        </thead>
        <tbody v-for="host in landingHosts" :key="host.id">
          <tr class="border-t border-n-slate-3 hover:bg-n-slate-1">
            <td class="px-4 py-3 font-mono text-n-slate-12 text-xs">
              {{ host.hostname }}
            </td>
            <td class="px-4 py-3 text-n-slate-11">
              {{ host.unit_code || '—' }}
            </td>
            <td class="px-4 py-3 text-n-slate-11">
              {{ host.auto_label || '—' }}
            </td>
            <td class="px-4 py-3 text-n-slate-11">
              <div class="flex items-center gap-2">
                <a
                  class="text-xs text-n-brand hover:underline"
                  :href="landingUrl(host.hostname)"
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  {{ labels.open }}
                </a>
                <button
                  class="text-xs text-n-slate-10 hover:text-n-slate-12"
                  @click="copyLink(host.hostname)"
                >
                  {{ labels.copy }}
                </button>
              </div>
            </td>
            <td class="px-4 py-3 text-right">
              <div class="flex items-center justify-end gap-3">
                <button
                  class="text-xs text-n-brand hover:underline font-medium transition-colors"
                  @click="openEdit(host)"
                >
                  {{ labels.edit }}
                </button>
                <button
                  class="text-xs text-ruby-9 hover:text-ruby-11 font-medium transition-colors"
                  @click="deleteHost(host.id)"
                >
                  {{ labels.remove }}
                </button>
              </div>
            </td>
          </tr>

          <!-- Formulário de Edição Inline -->
          <tr v-if="expandedHostId === host.id" class="bg-n-brand-1/30">
            <td colspan="5" class="p-4 border-t border-n-brand-3">
              <div
                class="bg-white dark:bg-slate-900 border border-n-brand-3 rounded-lg p-5 shadow-sm"
              >
                <h4 class="text-sm font-semibold text-n-slate-12 mb-4">
                  {{ labels.cfgTitle }}
                </h4>

                <div
                  class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 mb-4"
                >
                  <!-- Básico -->
                  <div>
                    <label
                      class="block text-xs font-medium text-n-slate-11 mb-1"
                      >{{ labels.labelHostname }}</label
                    >
                    <woot-input
                      v-model="editingHostData.hostname"
                      class="[&>input]:!mb-0"
                    />
                  </div>
                  <div>
                    <label
                      class="block text-xs font-medium text-n-slate-11 mb-1"
                      >{{ labels.labelCode }}</label
                    >
                    <woot-input
                      v-model="editingHostData.unit_code"
                      class="[&>input]:!mb-0"
                    />
                  </div>
                  <div>
                    <label
                      class="block text-xs font-medium text-n-slate-11 mb-1"
                      >{{ labels.labelAutoLabel }}</label
                    >
                    <woot-input
                      v-model="editingHostData.auto_label"
                      class="[&>input]:!mb-0"
                    />
                  </div>

                  <!-- Textos LP -->
                  <div class="sm:col-span-2">
                    <label
                      class="block text-xs font-medium text-n-slate-11 mb-1"
                      >{{ labels.cfgPageTitle }}</label
                    >
                    <woot-input
                      v-model="editingHostData.page_title"
                      class="[&>input]:!mb-0"
                    />
                  </div>
                  <div class="sm:col-span-3">
                    <label
                      class="block text-xs font-medium text-n-slate-11 mb-1"
                      >{{ labels.cfgPageSubtitle }}</label
                    >
                    <woot-input
                      v-model="editingHostData.page_subtitle"
                      class="[&>input]:!mb-0"
                    />
                  </div>

                  <!-- Botão e Aparência -->
                  <div>
                    <label
                      class="block text-xs font-medium text-n-slate-11 mb-1"
                      >{{ labels.cfgButtonText }}</label
                    >
                    <woot-input
                      v-model="editingHostData.button_text"
                      class="[&>input]:!mb-0"
                    />
                  </div>
                  <div>
                    <label
                      class="block text-xs font-medium text-n-slate-11 mb-1"
                      >{{ labels.cfgThemeColor }}</label
                    >
                    <div class="flex gap-2">
                      <input
                        v-model="editingHostData.theme_color"
                        type="color"
                        class="h-9 w-10 p-1 border border-n-slate-3 rounded cursor-pointer"
                      />
                      <woot-input
                        v-model="editingHostData.theme_color"
                        class="flex-1 [&>input]:!mb-0"
                      />
                    </div>
                  </div>
                  <div>
                    <label
                      class="block text-xs font-medium text-n-slate-11 mb-1"
                      >{{ labels.cfgLogoUrl }}</label
                    >
                    <woot-input
                      v-model="editingHostData.logo_url"
                      class="[&>input]:!mb-0"
                    />
                  </div>

                  <!-- WhatsApp e Tracking -->
                  <div>
                    <label
                      class="block text-xs font-medium text-n-slate-11 mb-1"
                      >{{ labels.cfgWhatsapp }}</label
                    >
                    <woot-input
                      v-model="editingHostData.whatsapp_number"
                      type="tel"
                      placeholder="5511999999999"
                      class="[&>input]:!mb-0"
                    />
                  </div>
                  <div class="sm:col-span-2">
                    <label
                      class="block text-xs font-medium text-n-slate-11 mb-1"
                      >{{ labels.cfgMessage }}</label
                    >
                    <woot-input
                      v-model="editingHostData.initial_message"
                      class="[&>input]:!mb-0"
                    />
                  </div>

                  <div>
                    <label
                      class="block text-xs font-medium text-n-slate-11 mb-1"
                      >{{ labels.cfgSource }}</label
                    >
                    <woot-input
                      v-model="editingHostData.default_source"
                      placeholder="direto"
                      class="[&>input]:!mb-0"
                    />
                  </div>
                  <div>
                    <label
                      class="block text-xs font-medium text-n-slate-11 mb-1"
                      >{{ labels.cfgCampaign }}</label
                    >
                    <woot-input
                      v-model="editingHostData.default_campanha"
                      placeholder="site"
                      class="[&>input]:!mb-0"
                    />
                  </div>
                </div>

                <!-- Seção de Promoções (Para IA) -->
                <div class="mt-4 pt-4 border-t border-n-slate-2">
                  <div class="flex items-center justify-between mb-4">
                    <h4 class="text-sm font-semibold text-n-slate-12">
                      {{ labels.promoSectionTitle }}
                    </h4>
                    <button
                      class="text-xs font-medium text-emerald-700 bg-emerald-50 hover:bg-emerald-100 px-3 py-1.5 rounded-md transition-colors flex items-center gap-1 border border-emerald-200"
                      @click.prevent="addPromotion"
                    >
                      <span class="text-base leading-none font-bold">+</span>
                      {{ labels.promoAdd }}
                    </button>
                  </div>

                  <div
                    v-for="(promo, index) in editingHostData.custom_config
                      .promotions"
                    :key="index"
                    class="bg-n-brand-1/10 p-5 rounded-lg border border-n-brand-2 mb-4 relative"
                  >
                    <button
                      class="absolute top-4 right-4 text-xs font-medium text-ruby-9 hover:text-ruby-11 transition-colors z-10"
                      @click.prevent="removePromotion(index)"
                    >
                      {{ labels.promoRemove }}
                    </button>

                    <div class="mb-4 flex items-center gap-2">
                      <input
                        :id="'promo-toggle-' + editingHostData.id + '-' + index"
                        v-model="promo.active"
                        type="checkbox"
                        class="h-4 w-4 rounded border-gray-300 text-n-brand cursor-pointer"
                      />
                      <label
                        :for="
                          'promo-toggle-' + editingHostData.id + '-' + index
                        "
                        class="text-sm font-medium text-n-slate-12 cursor-pointer"
                      >
                        {{ labels.promoTitle }}
                      </label>
                    </div>

                    <div
                      class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4"
                      :class="{
                        'opacity-50 pointer-events-none grayscale':
                          !promo.active,
                      }"
                    >
                      <div>
                        <label
                          class="block text-xs font-medium text-n-slate-11 mb-1"
                        >
                          {{ labels.promoChannel }} *
                        </label>
                        <woot-input
                          v-model="promo.channel"
                          placeholder="Ex: Instagram"
                          class="[&>input]:!mb-0"
                        />
                      </div>
                      <div class="sm:col-span-2">
                        <label
                          class="block text-xs font-medium text-n-slate-11 mb-1"
                        >
                          {{ labels.promoName }}
                        </label>
                        <woot-input
                          v-model="promo.title"
                          placeholder="Ex: Oferta Fim de Semana"
                          class="[&>input]:!mb-0"
                        />
                      </div>
                      <div class="sm:col-span-2">
                        <label
                          class="block text-xs font-medium text-n-slate-11 mb-1"
                        >
                          {{ labels.promoDesc }}
                        </label>
                        <woot-input
                          v-model="promo.description"
                          placeholder="Ex: 20% OFF na reserva sexta ou sábado. Válido para novos clientes."
                          class="[&>input]:!mb-0"
                        />
                      </div>
                      <div>
                        <label
                          class="block text-xs font-medium text-n-slate-11 mb-1"
                        >
                          {{ labels.promoCoupon }}
                        </label>
                        <woot-input
                          v-model="promo.coupon_code"
                          placeholder="Ex: BLACK20"
                          class="[&>input]:!mb-0"
                        />
                      </div>
                      <div>
                        <label
                          class="block text-xs font-medium text-n-slate-11 mb-1"
                        >
                          {{ labels.promoValid }}
                        </label>
                        <woot-input
                          v-model="promo.valid_until"
                          type="date"
                          class="[&>input]:!mb-0"
                        />
                      </div>
                    </div>
                  </div>

                  <div
                    v-if="
                      !editingHostData.custom_config.promotions ||
                      editingHostData.custom_config.promotions.length === 0
                    "
                    class="text-sm text-n-slate-10 italic py-4 text-center border border-dashed border-n-slate-3 rounded-lg"
                  >
                    {{ labels.promoEmpty }}
                  </div>
                </div>

                <div
                  class="mt-4 flex justify-end gap-3 border-t border-n-slate-2 pt-4"
                >
                  <NextButton
                    :label="labels.cfgCancel"
                    variant="hollow"
                    @click="cancelEdit"
                  />
                  <NextButton
                    :label="updateLabel"
                    :disabled="isUpdating"
                    @click="saveEdit"
                  />
                </div>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Formulário de adição rápida (somente hostname e unit_code) -->
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
        <div class="w-44">
          <label class="block text-xs font-medium text-n-slate-11 mb-1">
            {{ labels.labelAutoLabel }}
          </label>
          <woot-input
            v-model="newAutoLabel"
            :placeholder="labels.placeholderAutoLabel"
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
