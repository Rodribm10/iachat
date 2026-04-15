import CaptainLifecycleRulesAPI from 'dashboard/api/captain/lifecycleRules';
import { createStore } from '../storeFactory';
import { throwErrorMessage } from 'dashboard/store/utils/api';

export default createStore({
  name: 'CaptainLifecycleRule',
  API: CaptainLifecycleRulesAPI,
  actions: mutations => ({
    create: async ({ commit }, data) => {
      commit(mutations.SET_UI_FLAG, { creatingItem: true });
      try {
        const response = await CaptainLifecycleRulesAPI.create(data);
        commit(mutations.ADD, response.data);
        return response.data;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        commit(mutations.SET_UI_FLAG, { creatingItem: false });
      }
    },
    update: async ({ commit }, { id, ...data }) => {
      commit(mutations.SET_UI_FLAG, { updatingItem: true });
      try {
        const response = await CaptainLifecycleRulesAPI.update(id, data);
        commit(mutations.EDIT, response.data);
        return response.data;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        commit(mutations.SET_UI_FLAG, { updatingItem: false });
      }
    },
    delete: async ({ commit }, id) => {
      commit(mutations.SET_UI_FLAG, { deletingItem: true });
      try {
        await CaptainLifecycleRulesAPI.delete(id);
        commit(mutations.DELETE, id);
        return id;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        commit(mutations.SET_UI_FLAG, { deletingItem: false });
      }
    },
  }),
});
