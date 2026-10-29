export { videoPeople } from '../../lib/person-equipment.js';
const INTERVALS = { person: 3000, events: 3000, video: 30000, refresh: 2000 };
const positive = (value) => (typeof value === "number" && Number.isFinite(value) && value > 0 ? value : null);
const stamp = (value) => Date.parse(String(value).replace(" ", "T"));

export function isVitalAlert(event) {
  return event.status !== "已核验" && (event.vitalAlert === true || event.type === "生命体征");
}

export function currentVital(db, person, now) {
  if (!person) return { status: "暂无在册人员", values: [null, null, null], trend: [], time: "—", deviceId: "—" };
  const { watch, record, simulated } = db.vitals(person.id);
  const age = record ? stamp(now) - stamp(record.observedAt) : NaN;
  const status = !watch ? "未绑定手表" : simulated ? "模拟数据 · 非实时测量" : watch.online == null ? "暂无真实体征数据" : !watch.online ? "离线" : !record ? "暂无数据" : !Number.isFinite(age) || age < 0 || age > 10 * 60000 ? "数据过期" : "正常";
  const valid = status === "正常" || simulated;
  const seed = simulated;
  const values = valid
    ? [positive(record.heartRate), positive(record.oxygen), positive(record.skinTemperature)]
    : [null, null, null];
  let trend = [];
  if (valid) {
    trend = db
      .vitalHistory(person.id)
      .filter((item) => item.deviceId === record.deviceId && item.bindingId === record.bindingId && positive(item.heartRate) && item.observedAt <= record.observedAt)
      .slice(0, 5)
      .reverse()
      .map((item) => ({ value: item.heartRate, time: item.observedAt.slice(11, 16) }));
  }
  return { status, values, trend, time: record?.observedAt.slice(11) || "—", deviceId: watch?.id || "—", demo: seed };
}

export function eventWindow(events, offset, size = 3) {
  if (!events.length) return [];
  return Array.from({ length: Math.min(size, events.length) }, (_, index) => events[(offset + index) % events.length]);
}

export function nextPerson(people, id, step = 1) {
  if (!people.length) return "";
  const current = people.findIndex((person) => person.id === id);
  return people[(Math.max(0, current) + step + people.length) % people.length].id;
}

export { INTERVALS };
