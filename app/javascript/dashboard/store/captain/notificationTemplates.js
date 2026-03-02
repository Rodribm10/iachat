import CaptainNotificationTemplatesAPI from 'dashboard/api/captain/notificationTemplates';
import { throwErrorMessage } from 'dashboard/store/utils/api';

const state = {
  templates: [],
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
  },
};

const getters = {
  getTemplates: $state => $state.templates,
  getUIFlags: $state => $state.uiFlags,
};

const mutations = {
  SET_TEMPLATES($state, templates) {
    $state.templates = templates;
  },
  ADD_TEMPLATE($state, template) {
    $state.templates.push(template);
  },
  UPDATE_TEMPLATE($state, updated) {
    const index = $state.templates.findIndex(t => t.id === updated.id);
    if (index !== -1) $state.templates.splice(index, 1, updated);
  },
  DELETE_TEMPLATE($state, id) {
    $state.templates = $state.templates.filter(t => t.id !== id);
  },
  SET_UI_FLAG($state, flags) {
    $state.uiFlags = { ...$state.uiFlags, ...flags };
  },
};

const actions = {
  fetch: async ({ commit }, unitId) => {
    commit('SET_UI_FLAG', { isFetching: true });
    try {
      const { data } =
        await CaptainNotificationTemplatesAPI.getTemplates(unitId);
      commit('SET_TEMPLATES', data);
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },

  create: async ({ commit }, { unitId, ...templateData }) => {
    commit('SET_UI_FLAG', { isCreating: true });
    try {
      const { data } = await CaptainNotificationTemplatesAPI.createTemplate(
        unitId,
        templateData
      );
      commit('ADD_TEMPLATE', data);
      return data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isCreating: false });
    }
  },

  update: async ({ commit }, { unitId, id, ...templateData }) => {
    commit('SET_UI_FLAG', { isUpdating: true });
    try {
      const { data } = await CaptainNotificationTemplatesAPI.updateTemplate(
        unitId,
        id,
        templateData
      );
      commit('UPDATE_TEMPLATE', data);
      return data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isUpdating: false });
    }
  },

  delete: async ({ commit }, { unitId, id }) => {
    commit('SET_UI_FLAG', { isDeleting: true });
    try {
      await CaptainNotificationTemplatesAPI.deleteTemplate(unitId, id);
      commit('DELETE_TEMPLATE', id);
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isDeleting: false });
    }
  },
};

export default {
  namespaced: true,
  state,
  getters,
  mutations,
  actions,
};
