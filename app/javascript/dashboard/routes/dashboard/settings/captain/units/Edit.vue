<script>
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import SubmitButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    SubmitButton,
  },
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      name: '',
      inter_account_number: '',
      inter_pix_key: '',
      inter_client_id: '',
      inter_client_secret: '',
      inter_cert_content: '',
      inter_key_content: '',
      proactive_pix_polling_enabled: false,
      inbox_ids: [],
      hasInitialCert: false,
      hasInitialKey: false,
      hasInitialClientSecret: false,
    };
  },
  computed: {
    ...mapGetters({
      uiFlags: 'captainUnits/getUIFlags',
      records: 'captainUnits/getUnits',
      inboxes: 'inboxes/getInboxes',
    }),
    inboxOptions() {
      return this.inboxes.map(inbox => ({ id: inbox.id, name: inbox.name }));
    },
    isNew() {
      return this.$route.params.id === 'new';
    },
    isInterCredentialsReady() {
      return Boolean(
        this.inter_client_id &&
          (this.inter_client_secret || this.hasInitialClientSecret) &&
          this.inter_pix_key &&
          this.inter_account_number &&
          (this.inter_cert_content || this.hasInitialCert) &&
          (this.inter_key_content || this.hasInitialKey)
      );
    },
    pageTitle() {
      return this.isNew
        ? this.$t('CAPTAIN_SETTINGS.UNITS.ADD.TITLE')
        : this.$t('CAPTAIN_SETTINGS.UNITS.EDIT.TITLE');
    },
    pageDesc() {
      return this.isNew
        ? this.$t('CAPTAIN_SETTINGS.UNITS.ADD.DESC')
        : this.$t('CAPTAIN_SETTINGS.UNITS.EDIT.DESC');
    },
  },
  validations: {
    name: { required },
    inter_account_number: { required },
    inter_pix_key: { required },
  },
  mounted() {
    this.$store.dispatch('inboxes/get');
    if (!this.isNew) {
      this.fetchUnit();
    }
  },
  methods: {
    async fetchUnit() {
      if (!this.records.length) {
        await this.$store.dispatch('captainUnits/get');
      }
      const unit = this.records.find(
        u => u.id === Number(this.$route.params.id)
      );
      if (unit) {
        this.name = unit.name;
        this.inter_account_number = unit.inter_account_number;
        this.inter_pix_key = unit.inter_pix_key;
        this.inter_client_id = unit.inter_client_id;
        this.inbox_ids = unit.inbox_ids || [];
        this.proactive_pix_polling_enabled =
          !!unit.proactive_pix_polling_enabled;
        this.hasInitialCert = unit.has_cert;
        this.hasInitialKey = unit.has_key;
        this.hasInitialClientSecret = unit.has_client_secret;
      }
    },
    async submitForm() {
      this.v$.$touch();
      if (this.v$.$invalid) return;

      const payload = {
        name: this.name,
        inter_account_number: this.inter_account_number,
        inter_pix_key: this.inter_pix_key,
        inter_client_id: this.inter_client_id,
        inter_client_secret: this.inter_client_secret,
        inbox_ids: this.inbox_ids,
        inter_cert_content: this.inter_cert_content,
        inter_key_content: this.inter_key_content,
        proactive_pix_polling_enabled: this.isInterCredentialsReady
          ? this.proactive_pix_polling_enabled
          : false,
      };

      try {
        if (this.isNew) {
          await this.$store.dispatch('captainUnits/create', payload);
          useAlert(this.$t('CAPTAIN_SETTINGS.UNITS.ADD.API.SUCCESS_MESSAGE'));
        } else {
          await this.$store.dispatch('captainUnits/update', {
            id: this.$route.params.id,
            ...payload,
          });
          useAlert(this.$t('CAPTAIN_SETTINGS.UNITS.EDIT.API.SUCCESS_MESSAGE'));
        }
        this.$router.push({ name: 'captain_settings_units' });
      } catch (error) {
        const action = this.isNew ? 'ADD' : 'EDIT';
        const apiError =
          error?.response?.data?.errors?.join(' | ') ||
          error?.response?.data?.message;
        useAlert(
          apiError ||
            // eslint-disable-next-line
            this.$t(`CAPTAIN_SETTINGS.UNITS.${action}.API.ERROR_MESSAGE`)
        );
      }
    },
    triggerFileInput(refName) {
      this.$refs[refName].click();
    },
    handleFileUpload(event, targetField) {
      const file = event.target.files[0];
      if (!file) return;

      const reader = new FileReader();
      reader.onload = e => {
        this[targetField] = e.target.result;
      };
      reader.onerror = () => {
        useAlert(this.$t('CAPTAIN_SETTINGS.UNITS.EDIT.API.ERROR_MESSAGE'));
      };
      reader.readAsText(file);
    },
  },
};
</script>

<template>
  <div class="column content-box">
    <woot-modal-header :header-title="pageTitle" :header-content="pageDesc" />

    <form class="row" @submit.prevent="submitForm">
      <div class="small-12 columns">
        <label :class="{ error: v$.name.$error }">
          {{ $t('CAPTAIN_SETTINGS.UNITS.FORM.NAME.LABEL') }}
          <input
            v-model="name"
            type="text"
            :placeholder="$t('CAPTAIN_SETTINGS.UNITS.FORM.NAME.PLACEHOLDER')"
            @input="v$.name.$touch"
          />
          <span v-if="v$.name.$error" class="message">{{
            $t('CAPTAIN_SETTINGS.UNITS.FORM.NAME.ERROR')
          }}</span>
        </label>
      </div>

      <div class="small-12 columns">
        <label :class="{ error: v$.inter_account_number.$error }">
          {{ $t('CAPTAIN_SETTINGS.UNITS.FORM.INTER_ACCOUNT_NUMBER.LABEL') }}
          <input
            v-model="inter_account_number"
            type="text"
            :placeholder="
              $t('CAPTAIN_SETTINGS.UNITS.FORM.INTER_ACCOUNT_NUMBER.PLACEHOLDER')
            "
            @input="v$.inter_account_number.$touch"
          />
          <span v-if="v$.inter_account_number.$error" class="message">{{
            $t('CAPTAIN_SETTINGS.UNITS.FORM.INTER_ACCOUNT_NUMBER.ERROR')
          }}</span>
        </label>
      </div>

      <div class="small-12 columns">
        <label :class="{ error: v$.inter_pix_key.$error }">
          {{ $t('CAPTAIN_SETTINGS.UNITS.FORM.INTER_PIX_KEY.LABEL') }}
          <input
            v-model="inter_pix_key"
            type="text"
            :placeholder="
              $t('CAPTAIN_SETTINGS.UNITS.FORM.INTER_PIX_KEY.PLACEHOLDER')
            "
            @input="v$.inter_pix_key.$touch"
          />
          <span v-if="v$.inter_pix_key.$error" class="message">{{
            $t('CAPTAIN_SETTINGS.UNITS.FORM.INTER_PIX_KEY.ERROR')
          }}</span>
          <p class="help-text">
            {{ $t('CAPTAIN_SETTINGS.UNITS.FORM.INTER_PIX_KEY.HELP_TEXT') }}
          </p>
        </label>
      </div>

      <div class="small-12 columns">
        <label>
          {{ $t('CAPTAIN_SETTINGS.UNITS.INBOX.CONNECT_UNIT_LABEL') }}
          <div class="inbox-multiselect">
            <label
              v-for="option in inboxOptions"
              :key="option.id"
              class="inbox-option"
            >
              <input v-model="inbox_ids" type="checkbox" :value="option.id" />
              {{ option.name }}
            </label>
          </div>
          <p class="help-text">
            {{ $t('CAPTAIN_SETTINGS.UNITS.INBOX.CONNECT_UNIT_HELP') }}
          </p>
        </label>
      </div>

      <div class="small-12 columns">
        <label>
          {{ $t('CAPTAIN_SETTINGS.UNITS.FORM.INTER_CLIENT_ID.LABEL') }}
          <input
            v-model="inter_client_id"
            type="text"
            :placeholder="
              $t('CAPTAIN_SETTINGS.UNITS.FORM.INTER_CLIENT_ID.PLACEHOLDER')
            "
          />
        </label>
      </div>

      <div class="small-12 columns">
        <label>
          {{ $t('CAPTAIN_SETTINGS.UNITS.FORM.INTER_CLIENT_SECRET.LABEL') }}
          <input
            v-model="inter_client_secret"
            type="password"
            :placeholder="
              $t('CAPTAIN_SETTINGS.UNITS.FORM.INTER_CLIENT_SECRET.PLACEHOLDER')
            "
          />
        </label>
      </div>

      <div class="small-12 columns">
        <label>
          {{ $t('CAPTAIN_SETTINGS.UNITS.FORM.INTER_CERT_CONTENT.LABEL') }}
          <div class="file-upload-wrapper">
            <SubmitButton
              icon="i-lucide-upload"
              size="sm"
              variant="outline"
              color="slate"
              type="button"
              @click="triggerFileInput('certFile')"
            >
              {{
                $t(
                  'CAPTAIN_SETTINGS.UNITS.FORM.INTER_CERT_CONTENT.UPLOAD_BUTTON'
                )
              }}
            </SubmitButton>
            <input
              id="certFile"
              ref="certFile"
              type="file"
              accept=".crt,.pem"
              class="hidden-file-input"
              @change="handleFileUpload($event, 'inter_cert_content')"
            />
          </div>
          <textarea
            v-model="inter_cert_content"
            rows="5"
            :placeholder="
              $t('CAPTAIN_SETTINGS.UNITS.FORM.INTER_CERT_CONTENT.PLACEHOLDER')
            "
          />
          <p v-if="!isNew && hasInitialCert" class="help-text text-success">
            <fluent-icon icon="checkmark-circle" />
            {{ $t('CAPTAIN_SETTINGS.UNITS.FORM.CERT_PRESENT_HELP') }}
          </p>
        </label>
      </div>

      <div class="small-12 columns">
        <label>
          {{ $t('CAPTAIN_SETTINGS.UNITS.FORM.INTER_KEY_CONTENT.LABEL') }}
          <div class="file-upload-wrapper">
            <SubmitButton
              icon="i-lucide-upload"
              size="sm"
              variant="outline"
              color="slate"
              type="button"
              @click="triggerFileInput('keyFile')"
            >
              {{
                $t(
                  'CAPTAIN_SETTINGS.UNITS.FORM.INTER_KEY_CONTENT.UPLOAD_BUTTON'
                )
              }}
            </SubmitButton>
            <input
              id="keyFile"
              ref="keyFile"
              type="file"
              accept=".key,.pem"
              class="hidden-file-input"
              @change="handleFileUpload($event, 'inter_key_content')"
            />
          </div>
          <textarea
            v-model="inter_key_content"
            rows="5"
            :placeholder="
              $t('CAPTAIN_SETTINGS.UNITS.FORM.INTER_KEY_CONTENT.PLACEHOLDER')
            "
          />
          <p v-if="!isNew && hasInitialKey" class="help-text text-success">
            <fluent-icon icon="checkmark-circle" />
            {{ $t('CAPTAIN_SETTINGS.UNITS.FORM.CERT_PRESENT_HELP') }}
          </p>
        </label>
      </div>

      <div class="small-12 columns">
        <label>
          {{ $t('CAPTAIN_SETTINGS.UNITS.FORM.PROACTIVE_PIX_POLLING.LABEL') }}
        </label>
        <div class="checkbox-wrapper">
          <input
            id="proactive_pix_polling_enabled"
            v-model="proactive_pix_polling_enabled"
            type="checkbox"
            :disabled="!isInterCredentialsReady"
          />
          <label for="proactive_pix_polling_enabled" class="checkbox-label">
            {{
              $t(
                'CAPTAIN_SETTINGS.UNITS.FORM.PROACTIVE_PIX_POLLING.CHECKBOX_LABEL'
              )
            }}
          </label>
        </div>
        <p class="help-text">
          {{
            $t('CAPTAIN_SETTINGS.UNITS.FORM.PROACTIVE_PIX_POLLING.HELP_TEXT')
          }}
        </p>
        <p v-if="!isInterCredentialsReady" class="help-text">
          {{
            $t(
              'CAPTAIN_SETTINGS.UNITS.FORM.PROACTIVE_PIX_POLLING.DISABLED_HELP_TEXT'
            )
          }}
        </p>
      </div>

      <div class="small-12 columns">
        <div class="button-wrapper">
          <router-link
            :to="{ name: 'captain_settings_units' }"
            class="button clear"
          >
            {{ $t('CAPTAIN_SETTINGS.UNITS.FORM.CANCEL') }}
          </router-link>
          <SubmitButton
            :is-loading="uiFlags.isCreating || uiFlags.isUpdating"
            :disabled="v$.$invalid"
            type="submit"
          >
            {{ $t('CAPTAIN_SETTINGS.UNITS.FORM.SAVE') }}
          </SubmitButton>
        </div>
      </div>
    </form>
  </div>
</template>

<style scoped>
.inbox-multiselect {
  display: flex;
  flex-direction: column;
  gap: var(--space-smaller);
  margin-top: var(--space-micro);
  max-height: 180px;
  overflow-y: auto;
  border: 1px solid var(--s-200);
  border-radius: var(--border-radius-normal);
  padding: var(--space-small);
}
.inbox-option {
  display: flex;
  align-items: center;
  gap: var(--space-smaller);
  font-weight: normal;
  margin: 0;
  cursor: pointer;
}
</style>
