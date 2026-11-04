import { db, tick } from "@/mock/runtime";
import { workBusinessEnabled } from './work-business.js';
import { session } from "@/stores/session";

export function revision() {
  return tick.value;
}

export function scope(extra = {}) {
  return { station: session.station, ...extra, ...(!workBusinessEnabled(db) ? { workId: "" } : {}) };
}

export function people() {
  return db.state.people.filter((person) => person.station === session.station && person.active);
}

export function works() {
  return workBusinessEnabled(db) ? db.filter(db.state.works, scope()) : [];
}

export function events() {
  return db.filter(db.state.events, scope());
}

export function materials() {
  return db.filter(db.state.media, scope());
}

export function personName(id) {
  if (id === "operator") return "值守员";
  return db.person(id)?.name || "未分配";
}

export function statusColor(text) {
  if (text === "已核验") return "green";
  if (text === "处理中") return "blue";
  if (text === "待认领") return "red";
  return "yellow";
}

export function search(value, term) {
  return String(value || "")
    .toLowerCase()
    .includes(String(term || "").trim().toLowerCase());
}

export function helmetOf(personId) {
  return db.currentDevices(personId).find((device) => device.type === "H");
}
