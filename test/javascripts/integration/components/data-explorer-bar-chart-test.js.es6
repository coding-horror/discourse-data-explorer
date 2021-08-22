import componentTest, {
  setupRenderingTest,
} from "discourse/tests/helpers/component-test";
import { discourseModule, exists } from "discourse/tests/helpers/qunit-helpers";
import hbs from "htmlbars-inline-precompile";

discourseModule(
  "Data Explorer Plugin | Integration | Component | data-explorer-bar-chart",
  function (hooks) {
    setupRenderingTest(hooks);

    componentTest("it renders a chart", {
      template: hbs`{{data-explorer-bar-chart}}`,

      beforeEach() {
        this.set("labels", ["label_1", "label_2"]);
        this.set("values", [115, 1000]);
        this.set("datasetName", "data");
      },

      async test(assert) {
        assert.ok(exists("canvas"), "it renders a canvas");
      },
    });
  }
);
