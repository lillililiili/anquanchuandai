import { createApp } from "vue";
import App from "./App.vue";
import { router } from "./router";
import { db, guardianReady } from "./mock/runtime";
import { toast } from "./stores/notify";
import "./styles/index.css";

const app = createApp(App);
app.use(router);
Promise.all([router.isReady(), guardianReady]).then(() => {
  app.mount("#app");
  if (db.loadError) toast(db.loadError, true);
});
