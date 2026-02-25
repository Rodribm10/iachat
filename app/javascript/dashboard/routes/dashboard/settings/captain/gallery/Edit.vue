<script>
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import SubmitButton from 'dashboard/components-next/button/Button.vue';

const GLOBAL_SCOPE_VALUE = '__global__';

export default {
  components: {
    SubmitButton,
  },
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      inbox_scope_selection: GLOBAL_SCOPE_VALUE,
      suite_category: '',
      suite_number: '',
      description: '',
      active: true,
      image: null,
      currentImageUrl: '',
      previewImageUrl: '',
    };
  },
  computed: {
    ...mapGetters({
      uiFlags: 'captainGalleryItems/getUIFlags',
      items: 'captainGalleryItems/getItems',
      inboxes: 'inboxes/getInboxes',
    }),
    isNew() {
      return this.$route.params.id === 'new';
    },
    pageTitle() {
      return this.isNew
        ? this.$t('CAPTAIN_SETTINGS.GALLERY.ADD.TITLE')
        : this.$t('CAPTAIN_SETTINGS.GALLERY.EDIT.TITLE');
    },
    pageDesc() {
      return this.isNew
        ? this.$t('CAPTAIN_SETTINGS.GALLERY.ADD.DESC')
        : this.$t('CAPTAIN_SETTINGS.GALLERY.EDIT.DESC');
    },
    inboxOptions() {
      return [
        {
          id: GLOBAL_SCOPE_VALUE,
          name: this.$t('CAPTAIN_SETTINGS.GALLERY.FORM.INBOX.GLOBAL_OPTION'),
        },
        ...this.inboxes.map(inbox => ({
          id: inbox.id,
          name: inbox.name,
        })),
      ];
    },
    selectedScope() {
      if (
        this.inbox_scope_selection === GLOBAL_SCOPE_VALUE ||
        this.inbox_scope_selection === null
      ) {
        return 'global';
      }

      return 'inbox';
    },
    selectedInboxId() {
      if (this.selectedScope === 'global') {
        return null;
      }

      return this.inbox_scope_selection;
    },
    inboxHelpText() {
      if (this.selectedScope === 'global') {
        return this.$t('CAPTAIN_SETTINGS.GALLERY.FORM.INBOX.GLOBAL_HELP');
      }

      const selectedInbox = this.inboxes.find(
        inbox => String(inbox.id) === String(this.selectedInboxId)
      );

      if (!selectedInbox) {
        return this.$t('CAPTAIN_SETTINGS.GALLERY.FORM.INBOX.HELP');
      }

      return this.$t('CAPTAIN_SETTINGS.GALLERY.FORM.INBOX.SPECIFIC_HELP', {
        inbox: selectedInbox.name,
      });
    },
    imagePreview() {
      return this.previewImageUrl || this.currentImageUrl;
    },
  },
  validations() {
    return {
      suite_category: { required },
      suite_number: { required },
      description: { required },
      image: {
        required: this.isNew ? required : () => true,
      },
    };
  },
  async mounted() {
    await this.$store.dispatch('inboxes/get');

    if (!this.isNew) {
      await this.fetchItem();
    }
  },
  methods: {
    async fetchItem() {
      if (!this.items.length) {
        await this.$store.dispatch('captainGalleryItems/get');
      }

      const item = this.items.find(i => i.id === Number(this.$route.params.id));
      if (!item) return;

      this.inbox_scope_selection =
        item.scope === 'inbox' && item.inbox_id
          ? item.inbox_id
          : GLOBAL_SCOPE_VALUE;
      this.suite_category = item.suite_category;
      this.suite_number = item.suite_number;
      this.description = item.description;
      this.active = item.active;
      this.currentImageUrl = item.image_url;
    },
    onFileChange(event) {
      const file = event.target.files[0];
      if (!file) return;

      this.image = file;
      this.v$.image.$touch();
      this.previewImageUrl = URL.createObjectURL(file);
    },
    async submitForm() {
      this.v$.$touch();
      if (this.v$.$invalid) return;

      const formData = new FormData();
      formData.append('captain_gallery_item[scope]', this.selectedScope);
      if (this.selectedInboxId) {
        formData.append('captain_gallery_item[inbox_id]', this.selectedInboxId);
      }
      formData.append(
        'captain_gallery_item[suite_category]',
        this.suite_category
      );
      formData.append('captain_gallery_item[suite_number]', this.suite_number);
      formData.append('captain_gallery_item[description]', this.description);
      formData.append('captain_gallery_item[active]', this.active);
      if (this.image) {
        formData.append('captain_gallery_item[image]', this.image);
      }

      try {
        if (this.isNew) {
          await this.$store.dispatch('captainGalleryItems/create', formData);
          useAlert(this.$t('CAPTAIN_SETTINGS.GALLERY.ADD.API.SUCCESS_MESSAGE'));
        } else {
          await this.$store.dispatch('captainGalleryItems/update', {
            id: this.$route.params.id,
            formData,
          });
          useAlert(
            this.$t('CAPTAIN_SETTINGS.GALLERY.EDIT.API.SUCCESS_MESSAGE')
          );
        }
        this.$router.push({ name: 'captain_settings_gallery' });
      } catch (error) {
        const firstError = error?.response?.data?.errors?.[0];
        const fallbackMessage = this.isNew
          ? this.$t('CAPTAIN_SETTINGS.GALLERY.ADD.API.ERROR_MESSAGE')
          : this.$t('CAPTAIN_SETTINGS.GALLERY.EDIT.API.ERROR_MESSAGE');
        useAlert(firstError || fallbackMessage);
      }
    },
  },
};
</script>

<template>
  <div class="column content-box">
    <woot-modal-header :header-title="pageTitle" :header-content="pageDesc" />

    <form class="row" @submit.prevent="submitForm">
      <div class="small-12 columns">
        <label>
          {{ $t('CAPTAIN_SETTINGS.GALLERY.FORM.INBOX.LABEL') }}
          <select v-model="inbox_scope_selection">
            <option
              v-for="option in inboxOptions"
              :key="option.id"
              :value="option.id"
            >
              {{ option.name }}
            </option>
          </select>
          <p class="help-text">
            {{ inboxHelpText }}
          </p>
        </label>
      </div>

      <div class="small-12 columns">
        <label :class="{ error: v$.suite_category.$error }">
          {{ $t('CAPTAIN_SETTINGS.GALLERY.FORM.SUITE_CATEGORY.LABEL') }}
          <input
            v-model="suite_category"
            type="text"
            :placeholder="
              $t('CAPTAIN_SETTINGS.GALLERY.FORM.SUITE_CATEGORY.PLACEHOLDER')
            "
            @input="v$.suite_category.$touch"
          />
          <span v-if="v$.suite_category.$error" class="message">
            {{ $t('CAPTAIN_SETTINGS.GALLERY.FORM.SUITE_CATEGORY.ERROR') }}
          </span>
        </label>
      </div>

      <div class="small-12 columns">
        <label :class="{ error: v$.suite_number.$error }">
          {{ $t('CAPTAIN_SETTINGS.GALLERY.FORM.SUITE_NUMBER.LABEL') }}
          <input
            v-model="suite_number"
            type="text"
            :placeholder="
              $t('CAPTAIN_SETTINGS.GALLERY.FORM.SUITE_NUMBER.PLACEHOLDER')
            "
            @input="v$.suite_number.$touch"
          />
          <span v-if="v$.suite_number.$error" class="message">
            {{ $t('CAPTAIN_SETTINGS.GALLERY.FORM.SUITE_NUMBER.ERROR') }}
          </span>
        </label>
      </div>

      <div class="small-12 columns">
        <label :class="{ error: v$.description.$error }">
          {{ $t('CAPTAIN_SETTINGS.GALLERY.FORM.DESCRIPTION.LABEL') }}
          <textarea
            v-model="description"
            rows="3"
            :placeholder="
              $t('CAPTAIN_SETTINGS.GALLERY.FORM.DESCRIPTION.PLACEHOLDER')
            "
            @input="v$.description.$touch"
          />
          <span v-if="v$.description.$error" class="message">
            {{ $t('CAPTAIN_SETTINGS.GALLERY.FORM.DESCRIPTION.ERROR') }}
          </span>
        </label>
      </div>

      <div class="small-12 columns">
        <label :class="{ error: v$.image.$error }">
          {{ $t('CAPTAIN_SETTINGS.GALLERY.FORM.IMAGE.LABEL') }}
          <input type="file" accept="image/*" @change="onFileChange" />
          <span v-if="v$.image.$error" class="message">
            {{ $t('CAPTAIN_SETTINGS.GALLERY.FORM.IMAGE.ERROR') }}
          </span>
          <p class="help-text">
            {{ $t('CAPTAIN_SETTINGS.GALLERY.FORM.IMAGE.HELP_TEXT') }}
          </p>
        </label>
      </div>

      <div v-if="imagePreview" class="small-12 columns">
        <img
          :src="imagePreview"
          :alt="$t('CAPTAIN_SETTINGS.GALLERY.FORM.IMAGE.PREVIEW_ALT')"
          class="h-48 rounded object-cover"
        />
      </div>

      <div class="small-12 columns">
        <label>
          <input v-model="active" type="checkbox" />
          {{ $t('CAPTAIN_SETTINGS.GALLERY.FORM.ACTIVE.LABEL') }}
        </label>
      </div>

      <div class="small-12 columns button-group">
        <SubmitButton
          type="submit"
          :is-loading="uiFlags.isCreating || uiFlags.isUpdating"
          :label="
            isNew
              ? $t('CAPTAIN_SETTINGS.GALLERY.ADD.SUBMIT_BUTTON_TEXT')
              : $t('CAPTAIN_SETTINGS.GALLERY.EDIT.SUBMIT_BUTTON_TEXT')
          "
        />
      </div>
    </form>
  </div>
</template>
