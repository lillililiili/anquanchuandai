import { createApp } from "vue";
import App from "./App.vue";
import { router } from "./router";
import { db } from "./mock/runtime";
import { toast } from "./stores/notify";
import "./styles/index.css";

const app = createApp(App);
app.use(router);
router.isReady().then(() => {
  app.mount("#app");
  if (db.loadError) toast(db.loadError, true);
});
