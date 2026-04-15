import CaptainLifecycleDeliveriesAPI from 'dashboard/api/captain/lifecycleDeliveries';
import { createStore } from '../storeFactory';

export default createStore({
  name: 'CaptainLifecycleDelivery',
  API: CaptainLifecycleDeliveriesAPI,
});
