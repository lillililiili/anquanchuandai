import { installUiSpec } from "@ui-spec/install";
import { createApp } from "vue";
import App from "./App.vue";
import { router } from "./router";
import { db, guardianReady } from "./mock/runtime";
import { toast } from "./stores/notify";
import "./styles/index.css";
import "@ui-spec/tokens.css";
import "./styles/spec-theme.css";
import "./styles/spec-screen.css";
import "./styles/spec-adapter.css";
import "@ui-spec/controls.css";
import "@ui-spec/icon-masks.css";


const app = createApp(App);
installUiSpec(app);
app.use(router);
Promise.all([router.isReady(), guardianReady]).then(() => {
  app.mount("#app");
  if (db.loadError) toast(db.loadError, true);
});
