import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import types from '../mutation-types';
import CaptainGalleryItemsAPI from '../../api/captain/galleryItems';

export const state = {
  records: [],
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
  },
};

export const getters = {
  getItems: $state => $state.records,
  getUIFlags: $state => $state.uiFlags,
};

export const actions = {
  get: async ({ commit }, params = {}) => {
    commit(types.SET_CAPTAIN_GALLERY_UI_FLAG, { isFetching: true });
    try {
      const response = await CaptainGalleryItemsAPI.getItems(params);
      commit(types.SET_CAPTAIN_GALLERY_ITEMS, response.data);
    } catch (error) {
      // Ignore error
    } finally {
      commit(types.SET_CAPTAIN_GALLERY_UI_FLAG, { isFetching: false });
    }
  },

  create: async ({ commit }, formData) => {
    commit(types.SET_CAPTAIN_GALLERY_UI_FLAG, { isCreating: true });
    try {
      const response = await CaptainGalleryItemsAPI.createItem(formData);
      commit(types.ADD_CAPTAIN_GALLERY_ITEM, response.data);
      return response;
    } finally {
      commit(types.SET_CAPTAIN_GALLERY_UI_FLAG, { isCreating: false });
    }
  },

  update: async ({ commit }, { id, formData }) => {
    commit(types.SET_CAPTAIN_GALLERY_UI_FLAG, { isUpdating: true });
    try {
      const response = await CaptainGalleryItemsAPI.updateItem(id, formData);
      commit(types.EDIT_CAPTAIN_GALLERY_ITEM, response.data);
      return response;
    } finally {
      commit(types.SET_CAPTAIN_GALLERY_UI_FLAG, { isUpdating: false });
    }
  },

  delete: async ({ commit }, id) => {
    commit(types.SET_CAPTAIN_GALLERY_UI_FLAG, { isDeleting: true });
    try {
      await CaptainGalleryItemsAPI.deleteItem(id);
      commit(types.DELETE_CAPTAIN_GALLERY_ITEM, id);
    } finally {
      commit(types.SET_CAPTAIN_GALLERY_UI_FLAG, { isDeleting: false });
    }
  },
};

export const mutations = {
  [types.SET_CAPTAIN_GALLERY_UI_FLAG](_state, data) {
    _state.uiFlags = {
      ..._state.uiFlags,
      ...data,
    };
  },
  [types.SET_CAPTAIN_GALLERY_ITEMS]: MutationHelpers.set,
  [types.ADD_CAPTAIN_GALLERY_ITEM]: MutationHelpers.create,
  [types.EDIT_CAPTAIN_GALLERY_ITEM]: MutationHelpers.update,
  [types.DELETE_CAPTAIN_GALLERY_ITEM]: MutationHelpers.destroy,
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
