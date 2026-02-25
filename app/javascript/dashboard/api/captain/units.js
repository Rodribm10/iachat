import ApiClient from '../../api/ApiClient';

class CaptainUnitsAPI extends ApiClient {
  constructor() {
    super('captain/units', { accountScoped: true });
  }

  getUnits() {
    return this.get();
  }

  getUnit(id) {
    return this.show(id);
  }

  createUnit(data) {
    return this.create({ captain_unit: data });
  }

  updateUnit(id, data) {
    return this.update(id, { captain_unit: data });
  }

  deleteUnit(id) {
    return this.delete(id);
  }
}

export default new CaptainUnitsAPI();
