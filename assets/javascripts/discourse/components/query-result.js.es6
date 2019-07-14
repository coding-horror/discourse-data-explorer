import { ajax } from "discourse/lib/ajax";
import Badge from "discourse/models/badge";
import { getOwner } from "discourse-common/lib/get-owner";
import { default as computed } from "ember-addons/ember-computed-decorators";

function randomIdShort() {
  return "xxxxxxxx".replace(/[xy]/g, () => {
    /*eslint-disable*/
    return ((Math.random() * 16) | 0).toString(16);
    /*eslint-enable*/
  });
}

function transformedRelTable(table, modelClass) {
  const result = {};
  table.forEach(item => {
    if (modelClass) {
      result[item.id] = modelClass.create(item);
    } else {
      result[item.id] = item;
    }
  });
  return result;
}

const QueryResultComponent = Ember.Component.extend({
  layoutName: "explorer-query-result",

  rows: Ember.computed.alias("content.rows"),
  columns: Ember.computed.alias("content.columns"),
  params: Ember.computed.alias("content.params"),
  explainText: Ember.computed.alias("content.explain"),
  hasExplain: Ember.computed.notEmpty("content.explain"),

  @computed("content.result_count")
  resultCount(count) {
    if (count === this.get("content.default_limit")) {
      return I18n.t("explorer.max_result_count", { count });
    } else {
      return I18n.t("explorer.result_count", { count });
    }
  },

  colCount: Ember.computed.reads("content.columns.length"),

  @computed("content.duration")
  duration(contentDuration) {
    return I18n.t("explorer.run_time", {
      value: I18n.toNumber(contentDuration, { precision: 1 })
    });
  },

  @computed("params.[]")
  parameterAry(params) {
    let arr = [];
    for (var key in params) {
      if (params.hasOwnProperty(key)) {
        arr.push({ key, value: params[key] });
      }
    }
    return arr;
  },

  @computed("content", "columns.[]")
  columnDispNames(content, columns) {
    if (!columns) {
      return [];
    }
    return columns.map(colName => {
      if (colName.endsWith("_id")) {
        return colName.slice(0, -3);
      }
      const dIdx = colName.indexOf("$");
      if (dIdx >= 0) {
        return colName.substring(dIdx + 1);
      }
      return colName;
    });
  },

  @computed
  fallbackTemplate() {
    return getOwner(this).lookup("template:explorer/text.raw");
  },

  @computed("content", "columns.[]")
  columnTemplates(content, columns) {
    if (!columns) {
      return [];
    }
    return columns.map((colName, idx) => {
      let viewName = "text";
      if (this.get("content.colrender")[idx]) {
        viewName = this.get("content.colrender")[idx];
      }

      // After `findRawTemplates` is in stable this should be updated to use that
      let template = getOwner(this).lookup(`template:explorer/${viewName}.raw`);
      if (!template) {
        template = Discourse.RAW_TEMPLATES[`javascripts/explorer/${viewName}`];
      }

      return { name: viewName, template };
    });
  },

  @computed("content.relations.user")
  transformedUserTable(contentRelationsUser) {
    return transformedRelTable(contentRelationsUser);
  },
  @computed("content.relations.badge")
  transformedBadgeTable(contentRelationsBadge) {
    return transformedRelTable(contentRelationsBadge, Badge);
  },
  @computed("content.relations.post")
  transformedPostTable(contentRelationsPost) {
    return transformedRelTable(contentRelationsPost);
  },
  @computed("content.relations.topic")
  transformedTopicTable(contentRelationsTopic) {
    return transformedRelTable(contentRelationsTopic);
  },

  @computed("site.groups")
  transformedGroupTable(groups) {
    return transformedRelTable(groups);
  },

  lookupUser(id) {
    return this.transformedUserTable[id];
  },
  lookupBadge(id) {
    return this.transformedBadgeTable[id];
  },
  lookupPost(id) {
    return this.transformedPostTable[id];
  },
  lookupTopic(id) {
    return this.transformedTopicTable[id];
  },
  lookupGroup(id) {
    return this.transformedGroupTable[id];
  },

  lookupCategory(id) {
    return this.site.get("categoriesById")[id];
  },

  downloadResult(format) {
    // Create a frame to submit the form in (?)
    // to avoid leaving an about:blank behind
    let windowName = randomIdShort();
    const newWindowContents =
      "<style>body{font-size:36px;display:flex;justify-content:center;align-items:center;}</style><body>Click anywhere to close this window once the download finishes.<script>window.onclick=function(){window.close()};</script>";

    window.open("data:text/html;base64," + btoa(newWindowContents), windowName);

    let form = document.createElement("form");
    form.setAttribute("id", "query-download-result");
    form.setAttribute("method", "post");
    form.setAttribute(
      "action",
      Discourse.getURL(
        "/admin/plugins/explorer/queries/" +
          this.get("query.id") +
          "/run." +
          format +
          "?download=1"
      )
    );
    form.setAttribute("target", windowName);
    form.setAttribute("style", "display:none;");

    function addInput(name, value) {
      let field;
      field = document.createElement("input");
      field.setAttribute("name", name);
      field.setAttribute("value", value);
      form.appendChild(field);
    }

    addInput("params", JSON.stringify(this.params));
    addInput("explain", this.hasExplain);
    addInput("limit", "1000000");

    ajax("/session/csrf.json").then(csrf => {
      addInput("authenticity_token", csrf.csrf);

      document.body.appendChild(form);
      form.submit();
      Ember.run.schedule("afterRender", () => document.body.removeChild(form));
    });
  },

  actions: {
    downloadResultJson() {
      this.downloadResult("json");
    },
    downloadResultCsv() {
      this.downloadResult("csv");
    }
  }
});

export default QueryResultComponent;
