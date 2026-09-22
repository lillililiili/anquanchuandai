import { ref } from "vue";
import { createStore } from "./data.js";

const storage = typeof localStorage === "undefined" ? null : localStorage;

export const db = createStore(storage);
export const tick = ref(0);

db.subscribe(() => {
  tick.value += 1;
});
