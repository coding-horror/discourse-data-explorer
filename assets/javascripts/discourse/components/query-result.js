import { findRawTemplate } from "discourse-common/lib/raw-templates";
import I18n from "I18n";
import { ajax } from "discourse/lib/ajax";
import getURL from "discourse-common/lib/get-url";
import Badge from "discourse/models/badge";
import { default as computed } from "discourse-common/utils/decorators";

function randomIdShort() {
  return "xxxxxxxx".replace(/[xy]/g, () => {
    /*eslint-disable*/
    return ((Math.random() * 16) | 0).toString(16);
    /*eslint-enable*/
  });
}

function transformedRelTable(table, modelClass) {
  const result = {};
  table.forEach((item) => {
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
  chartDatasetName: Ember.computed.reads("columnDispNames.1"),
  chartValues: Ember.computed.mapBy("content.rows", "1"),
  showChart: false,

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
      value: I18n.toNumber(contentDuration, { precision: 1 }),
    });
  },

  @computed("params.[]")
  parameterAry(params) {
    let arr = [];
    for (let key in params) {
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
    return columns.map((colName) => {
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
    return findRawTemplate("javascripts/explorer/text");
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

      const template = findRawTemplate(`javascripts/explorer/${viewName}`);

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

  @computed(
    "rows.[]",
    "content.colrender.[]",
    "content.result_count",
    "colCount"
  )
  canShowChart(rows, colRender, resultCount, colCount) {
    const hasTwoColumns = colCount === 2;
    const secondColumnContainsNumber =
      resultCount > 0 && typeof rows[0][1] === "number";
    const secondColumnContainsId = colRender[1];

    return (
      hasTwoColumns && secondColumnContainsNumber && !secondColumnContainsId
    );
  },

  @computed("content.rows.[]", "content.colrender.[]")
  chartLabels(rows, colRender) {
    const labelSelectors = {
      user: (user) => user.username,
      badge: (badge) => badge.name,
      topic: (topic) => topic.title,
      group: (group) => group.name,
      category: (category) => category.name,
    };

    const relationName = colRender[0];

    if (relationName) {
      const lookupFunc = this[`lookup${relationName.capitalize()}`];
      const labelSelector = labelSelectors[relationName];

      if (lookupFunc && labelSelector) {
        return rows.map((r) => {
          const relation = lookupFunc.call(this, r[0]);
          const label = labelSelector(relation);
          return this._cutChartLabel(label);
        });
      }
    }

    return rows.map((r) => this._cutChartLabel(r[0]));
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

  download_url() {
    return this.group
      ? `/g/${this.group.name}/reports/`
      : "/admin/plugins/explorer/queries/";
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
      getURL(
        this.download_url() +
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

    ajax("/session/csrf.json").then((csrf) => {
      addInput("authenticity_token", csrf.csrf);

      document.body.appendChild(form);
      form.submit();
      Ember.run.schedule("afterRender", () => document.body.removeChild(form));
    });
  },

  _cutChartLabel(label) {
    const labelString = label.toString();
    if (labelString.length > 25) {
      return `${labelString.substring(0, 25)}...`;
    } else {
      return labelString;
    }
  },

  actions: {
    downloadResultJson() {
      this.downloadResult("json");
    },
    downloadResultCsv() {
      this.downloadResult("csv");
    },
    showChart() {
      this.set("showChart", true);
    },
    showTable() {
      this.set("showChart", false);
    },
  },
});

export default QueryResultComponent;
