import { createStore } from "../src/mock/data.js";
import fs from "node:fs";

const db = createStore(null);
const out = "E:/沉积岩/anquanchuandai/后端代码/melhat_server-dev/ruoyi-admin/src/main/resources/guardian-seed.json";
fs.writeFileSync(out, JSON.stringify(db.state));
if (!/[\u4e00-\u9fff]/.test(db.state.stations[0].name)) {
  throw new Error("seed Chinese was lost");
}
console.log(db.state.stations[0].name, db.state.people.length, db.state.events.length);
