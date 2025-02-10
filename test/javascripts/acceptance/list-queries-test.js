import { visit } from "@ember/test-helpers";
import { test } from "qunit";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";
import { i18n } from "discourse-i18n";

acceptance("Data Explorer Plugin | List Queries", function (needs) {
  needs.user();
  needs.settings({ data_explorer_enabled: true });

  needs.pretender((server, helper) => {
    server.get("/admin/plugins/explorer/groups.json", () => {
      return helper.response([
        {
          id: 1,
          name: "admins",
        },
        {
          id: 2,
          name: "moderators",
        },
        {
          id: 3,
          name: "staff",
        },
        {
          id: 0,
          name: "everyone",
        },
        {
          id: 10,
          name: "trust_level_0",
        },
        {
          id: 11,
          name: "trust_level_1",
        },
        {
          id: 12,
          name: "trust_level_2",
        },
        {
          id: 13,
          name: "trust_level_3",
        },
        {
          id: 14,
          name: "trust_level_4",
        },
      ]);
    });

    server.get("/admin/plugins/explorer/schema.json", () => {
      return helper.response({
        anonymous_users: [
          {
            column_name: "id",
            data_type: "serial",
            primary: true,
          },
          {
            column_name: "user_id",
            data_type: "integer",
            fkey_info: "users",
          },
          {
            column_name: "master_user_id",
            data_type: "integer",
            fkey_info: "users",
          },
          {
            column_name: "active",
            data_type: "boolean",
          },
          {
            column_name: "created_at",
            data_type: "timestamp",
          },
          {
            column_name: "updated_at",
            data_type: "timestamp",
          },
        ],
      });
    });

    server.get("/admin/plugins/explorer/queries", () => {
      return helper.response({
        queries: [
          {
            id: -5,
            name: "Top 100 Active Topics",
            description:
              "based on the number of replies, it accepts a ‘months_ago’ parameter, defaults to 1 to give results for the last calendar month.",
            username: "system",
            group_ids: [],
            last_run_at: "2021-02-08T15:37:49.188Z",
            user_id: -1,
          },
          {
            id: -6,
            name: "Top 100 Likers",
            description:
              "returns the top 100 likers for a given monthly period ordered by like_count. It accepts a ‘months_ago’ parameter, defaults to 1 to give results for the last calendar month.",
            username: "system",
            group_ids: [],
            last_run_at: "2021-02-11T08:29:59.337Z",
            user_id: -1,
          },
        ],
      });
    });
  });

  test("renders the page with the list of queries", async function (assert) {
    await visit("/admin/plugins/explorer");

    assert
      .dom("div.query-list input.ember-text-field")
      .hasAttribute(
        "placeholder",
        i18n("explorer.search_placeholder"),
        "the search box was rendered"
      );

    assert
      .dom("div.query-list button.btn-icon svg.d-icon-plus")
      .exists("the add query button was rendered");

    assert
      .dom("div.query-list button.btn-icon-text span.d-button-label")
      .hasText(i18n("explorer.import.label"), "the import button was rendered");

    assert
      .dom("div.container table.recent-queries tbody tr")
      .exists({ count: 2 }, "the list of queries was rendered");

    assert
      .dom("div.container table.recent-queries tbody tr:nth-child(1) td a")
      .hasText(/^\s*Top 100 Likers/, "The first query was rendered");

    assert
      .dom("div.container table.recent-queries tbody tr:nth-child(2) td a")
      .hasText(/^\s*Top 100 Active Topics/, "The second query was rendered");
  });
});
