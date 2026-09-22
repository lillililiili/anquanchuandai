/* Read-only dashboard projection. No writes to personnel, bindings or observations. */
(function (root) {
  "use strict";
  const INTERVALS = {person: 3000, events: 3000, video: 3000, refresh: 2000};
  const positive = value => typeof value === "number" && Number.isFinite(value) && value > 0 ? value : null;
  const stamp = value => Date.parse(String(value).replace(" ", "T"));
  function currentVital(db, person, now) {
    if (!person) return {status: "暂无当班人员", values: [null, null, null], trend: [], time: "—", deviceId: "—"};
    const {watch, record} = db.vitals(person.id);
    const age = record ? stamp(now) - stamp(record.observedAt) : NaN;
    const status = !watch ? "未佩戴" : !watch.online ? "离线" : !record ? "暂无数据" : !Number.isFinite(age) || age > 10 * 60000 ? "数据过期" : "正常";
    const valid = status === "正常";
    const seed = record?.id === "VITAL-SEED-" + person.id && record.source === "预置观测";
    // Only the isolated, clearly labelled seed demonstration has synthetic skin/trend samples.
    // Body temperature is never relabelled or converted to skin temperature.
    const skinDemo = {P1: 34.2, P2: 34.5, P3: 34.1, P4: 34.6, P5: 34.3, P6: 34.4, P7: 34.2, P8: 34.3};
    const values = valid ? [positive(record.heartRate), positive(record.oxygen), positive(record.skinTemperature ?? (seed ? skinDemo[person.id] : null))] : [null, null, null];
    let trend = [];
    if (valid) {
      trend = db.vitalHistory(person.id).filter(v => v.deviceId === record.deviceId && v.bindingId === record.bindingId && positive(v.heartRate) && v.observedAt <= record.observedAt).slice(0, 5).reverse().map(v => ({value: v.heartRate, time: v.observedAt.slice(11, 16)}));
      if (seed && trend.length === 1) {
        const end = stamp(record.observedAt);
        trend = [-2, 1, -1, 2, 0].map((offset, i) => ({value: record.heartRate + offset, time: new Date(end - (4 - i) * 5 * 60000).toTimeString().slice(0, 5)}));
      }
    }
    return {status, values, trend, time: record?.observedAt.slice(11) || "—", deviceId: watch?.id || "—", demo: seed};
  }
  function eventWindow(events, offset, size = 3) {
    const urgent = events.filter(isVitalAlert), others = events.filter(e => !isVitalAlert(e));
    // Keep outstanding vital alerts continuously represented, even with more than one page.
    const fixed = urgent.slice(0, size);
    const pool = urgent.length > size ? urgent.slice(size).concat(others) : others;
    const slots = size - fixed.length;
    return fixed.concat(Array.from({length: Math.min(slots, pool.length)}, (_, i) => pool[(offset + i) % pool.length]));
  }
  function isVitalAlert(event) {
    return event.status !== "已核验" && (event.vitalAlert === true || event.type === "生命体征");
  }
  function videoPeople(db, people) {
    const eligible = people.filter(p => db.currentDevices(p.id).some(d => d.type === "H" && d.active && d.online && d.video === "available"));
    const first = [], rest = [], areas = new Set();
    eligible.forEach(p => { if (!areas.has(p.area) && first.length < 3) {first.push(p); areas.add(p.area);} else rest.push(p); });
    return first.concat(rest);
  }
  function nextPerson(people, id, step = 1) {
    if (!people.length) return "";
    const current = people.findIndex(p => p.id === id);
    return people[(Math.max(0, current) + step + people.length) % people.length].id;
  }
  const api = {INTERVALS, currentVital, eventWindow, isVitalAlert, videoPeople, nextPerson};
  if (typeof module !== "undefined") module.exports = api;
  else root.RollingScreenModel = api;
})(typeof window === "undefined" ? globalThis : window);
