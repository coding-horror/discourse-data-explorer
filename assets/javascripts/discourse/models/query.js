import RestModel from "discourse/models/rest";
import getURL from "discourse-common/lib/get-url";

export default class Query extends RestModel {
  static updatePropertyNames = [
    "name",
    "description",
    "sql",
    "user_id",
    "created_at",
    "group_ids",
    "last_run_at",
  ];

  params = {};

  constructor() {
    super(...arguments);
    this.param_info?.resetParams();
  }

  get downloadUrl() {
    return getURL(`/admin/plugins/explorer/queries/${this.id}.json?export=1`);
  }

  get hasParams() {
    return this.param_info.length;
  }

  resetParams() {
    const newParams = {};
    const oldParams = this.params;
    this.param_info.forEach((pinfo) => {
      const name = pinfo.identifier;
      if (oldParams[pinfo.identifier]) {
        newParams[name] = oldParams[name];
      } else if (pinfo["default"] !== null) {
        newParams[name] = pinfo["default"];
      } else if (pinfo["type"] === "boolean") {
        newParams[name] = "false";
      } else if (pinfo["type"] === "user_id") {
        newParams[name] = null;
      } else if (pinfo["type"] === "user_list") {
        newParams[name] = null;
      } else if (pinfo["type"] === "group_list") {
        newParams[name] = null;
      } else {
        newParams[name] = "";
      }
    });
    this.params = newParams;
  }

  updateProperties() {
    const props = this.getProperties(Query.updatePropertyNames);
    if (this.destroyed) {
      props.id = this.id;
    }
    return props;
  }

  createProperties() {
    if (this.sql) {
      // Importing
      return this.updateProperties();
    }
    return this.getProperties("name");
  }
}
