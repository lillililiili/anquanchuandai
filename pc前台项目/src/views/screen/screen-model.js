const INTERVALS = { person: 3000, events: 3000, video: 3000, refresh: 2000 };
const positive = (value) => (typeof value === "number" && Number.isFinite(value) && value > 0 ? value : null);
const stamp = (value) => Date.parse(String(value).replace(" ", "T"));

export function isVitalAlert(event) {
  return event.status !== "已核验" && (event.vitalAlert === true || event.type === "生命体征");
}

export function currentVital(db, person, now) {
  if (!person) return { status: "暂无当班人员", values: [null, null, null], trend: [], time: "—", deviceId: "—" };
  const { watch, record } = db.vitals(person.id);
  const age = record ? stamp(now) - stamp(record.observedAt) : NaN;
  const status = !watch ? "未佩戴" : !watch.online ? "离线" : !record ? "暂无数据" : !Number.isFinite(age) || age > 10 * 60000 ? "数据过期" : "正常";
  const valid = status === "正常";
  const seed = record?.id === "VITAL-SEED-" + person.id && record.source === "预置观测";
  const skinDemo = { P1: 34.2, P2: 34.5, P3: 34.1, P4: 34.6, P5: 34.3, P6: 34.4, P7: 34.2, P8: 34.3 };
  const values = valid
    ? [positive(record.heartRate), positive(record.oxygen), positive(record.skinTemperature ?? (seed ? skinDemo[person.id] : null))]
    : [null, null, null];
  let trend = [];
  if (valid) {
    trend = db
      .vitalHistory(person.id)
      .filter((item) => item.deviceId === record.deviceId && item.bindingId === record.bindingId && positive(item.heartRate) && item.observedAt <= record.observedAt)
      .slice(0, 5)
      .reverse()
      .map((item) => ({ value: item.heartRate, time: item.observedAt.slice(11, 16) }));
    if (seed && trend.length === 1) {
      const end = stamp(record.observedAt);
      trend = [-2, 1, -1, 2, 0].map((offset, index) => ({
        value: record.heartRate + offset,
        time: new Date(end - (4 - index) * 5 * 60000).toTimeString().slice(0, 5),
      }));
    }
  }
  return { status, values, trend, time: record?.observedAt.slice(11) || "—", deviceId: watch?.id || "—", demo: seed };
}

export function eventWindow(events, offset, size = 3) {
  if (!events.length) return [];
  return Array.from({ length: Math.min(size, events.length) }, (_, index) => events[(offset + index) % events.length]);
}

export function videoPeople(db, people) {
  const eligible = people.filter((person) =>
    db.currentDevices(person.id).some((device) => device.type === "H" && device.active && device.online && device.video === "available"),
  );
  const first = [];
  const rest = [];
  const areas = new Set();
  eligible.forEach((person) => {
    if (!areas.has(person.area) && first.length < 3) {
      first.push(person);
      areas.add(person.area);
    } else rest.push(person);
  });
  return first.concat(rest);
}

export function nextPerson(people, id, step = 1) {
  if (!people.length) return "";
  const current = people.findIndex((person) => person.id === id);
  return people[(Math.max(0, current) + step + people.length) % people.length].id;
}

export { INTERVALS };
