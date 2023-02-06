import getURL from "discourse-common/lib/get-url";
import RestModel from "discourse/models/rest";

export default class Query extends RestModel {
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
}

Query.reopenClass({
  updatePropertyNames: [
    "name",
    "description",
    "sql",
    "user_id",
    "created_at",
    "group_ids",
    "last_run_at",
  ],
});
