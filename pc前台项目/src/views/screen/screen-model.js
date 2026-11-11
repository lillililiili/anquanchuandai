export { videoPeople } from '../../lib/person-equipment.js';
import { formatBeijingDateTime } from '../../lib/date-time.js';
import { deviceStatus, isRealDevice, projectDevice } from '../../lib/device-telemetry.js';
import { featureState } from '../../../../shared/device-features.mjs';
import { serverNow } from '../../../../shared/server-clock.mjs';
const INTERVALS = { person: 3000, events: 3000, video: 30000, refresh: 2000 };
const positive = (value) => (typeof value === "number" && Number.isFinite(value) && value > 0 ? value : null);
const stamp = (value) => {
  const formatted = formatBeijingDateTime(value);
  return formatted === '—' ? NaN : Date.parse(formatted.replace(' ', 'T') + '+08:00');
};

export function isVitalAlert(event) {
  return event.status !== "已核验" && (event.vitalAlert === true || event.type === "生命体征");
}

export function currentVital(db, person, now) {
  if (!person) return { status: "暂无在册人员", values: [null, null, null], trend: [], time: "—", deviceId: "—" };
  const { watch, record, simulated } = db.vitals(person.id);
  const age = record ? stamp(now) - stamp(record.observedAt) : NaN;
  const status = !watch ? "未绑定手表" : simulated ? "模拟数据 · 非实时测量" : watch.online == null ? "暂无体征数据" : !watch.online ? "离线" : !record ? "暂无数据" : !Number.isFinite(age) || age < 0 || age > 10 * 60000 ? "数据过期" : "正常";
  const valid = status === "正常" || simulated;
  const seed = simulated;
  const values = valid
    ? [positive(record.heartRate), positive(record.oxygen), positive(record.skinTemperature)]
    : [null, null, null];
  let trend = [];
  if (valid) {
    trend = db
      .vitalHistory(person.id)
      .filter((item) => item.deviceId === record.deviceId && item.bindingId === record.bindingId && positive(item.heartRate) && stamp(item.observedAt) <= stamp(record.observedAt))
      .sort((a,b) => stamp(b.observedAt) - stamp(a.observedAt))
      .slice(0, 5)
      .reverse()
      .map((item) => ({ value: item.heartRate, time: formatBeijingDateTime(item.observedAt).slice(11, 16) }));
  }
  return { status, values, trend, time: formatBeijingDateTime(record?.observedAt), deviceId: watch?.id || "—", demo: seed };
}

export function personEquipmentMonitor(db, person) {
  const devices = person ? db.currentDevices(person.id).filter(device => device.active !== false && isRealDevice(device)).map(device => projectDevice(device)) : [];
  return [['H', '安全帽', 'helmet', '佩戴状态'], ['B', '安全带', 'harness', '双钩状态']].map(([type, name, image, detailLabel]) => {
    const device = devices.find(item => item.type === type);
    const status = device ? deviceStatus(device) : '未领用';
    const online = status === '在线';
    const battery = online && featureState(device, 'battery').available && Number.isFinite(device.battery) ? device.battery : null;
    const feature = featureState(device, type === 'H' ? 'wear' : 'hooks');
    let detail = device ? feature.supported ? '暂无有效上报' : '暂不支持' : '—';
    let detailTone = 'muted';
    if (online && feature.available) {
      if (type === 'H' && typeof device.worn === 'boolean') {
        detail = device.worn ? '已佩戴' : '未佩戴';
        detailTone = device.worn ? 'good' : 'warn';
      } else if (type === 'B') {
        const hooks = [device.hookAEngaged, device.hookBEngaged];
        detail = hooks.map(value => value === true ? '已挂接' : value === false ? '未挂接' : '未知').join(' / ');
        detailTone = hooks.every(value => value === true) ? 'good' : hooks.some(value => value === false) ? 'warn' : 'muted';
      }
    }
    return { type, name, image, deviceId: device?.id || '未领用', status,
      statusTone: online ? 'good' : device ? 'warn' : 'muted',
      battery, detailLabel, detail, detailTone };
  });
}

export function eventActivity(events, now = serverNow()) {
  const end = typeof now === 'number' ? now : stamp(now);
  const period = 4 * 60 * 60 * 1000;
  const start = end - 6 * period;
  const buckets = Array.from({ length: 6 }, (_, index) => {
    const from = start + index * period, to = from + period;
    const fromText = formatBeijingDateTime(new Date(from).toISOString());
    const toText = formatBeijingDateTime(new Date(to).toISOString());
    return { count: 0, label: fromText.slice(11, 16), range: `${fromText.slice(5, 16)} 至 ${toText.slice(5, 16)}` };
  });
  let undated = 0;
  for (const event of events) {
    let occurred = stamp(event.occurredAt);
    if (!Number.isFinite(occurred)) occurred = stamp(event.date && event.time ? `${event.date} ${event.time}` : event.time);
    if (!Number.isFinite(occurred)) { undated++; continue; }
    if (occurred < start || occurred > end) continue;
    buckets[Math.min(5, Math.floor((occurred - start) / period))].count++;
  }
  return { buckets, undated };
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
