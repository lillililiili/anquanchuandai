import { serverNow } from './server-clock.mjs';

// Display values retain their individual report times. A GPS callback must not
// imply that an older battery, TF or pressure measurement is current.
export function splitHelmetTelemetry(device, now = serverNow()) {
  const number = (value, min = 0) => value !== null && value !== '' && value !== undefined && Number.isFinite(Number(value)) && Number(value) >= min ? Number(value) : null;
  const ageLabel = (value, freshness) => {
    const time = Date.parse(value || ''), age = now - time;
    return freshness === 'CURRENT' && Number.isFinite(time) && age >= 0 && age <= 300000 ? '近期上报' : Number.isFinite(time) ? '最后上报' : '时间未确认';
  };
  const tf = device?.tfStorage || device?.storage || {};
  const pressure = number(device?.pressure ?? device?.baroPressure ?? device?.baro?.pressure);
  const total = device?.storageTotal ?? device?.tfTotal ?? tf.total ?? tf.totalSize;
  const free = device?.storageAvailable ?? device?.tfFree ?? tf.free ?? tf.freeSize;
  const tfAt = device?.storageAvailableReportedAt ?? device?.storageTotalReportedAt ?? device?.tfReportedAt ?? device?.storageReportedAt ?? tf.reportedAt;
  const pressureAt = device?.pressureReportedAt ?? device?.baroReportedAt ?? device?.baro?.reportedAt;
  const field = (key, label, value) => ({ key, label, value: value ?? '未上报', reportedAt: device?.[`${key}ReportedAt`], status: ageLabel(device?.[`${key}ReportedAt`], device?.[`${key}Freshness`]) });
  const rawStorage = value => value == null || value === '' ? null : String(value) + '（设备原始值）';
  const enabled = device?.tfEnable;
  const storageFields = [
    field('tfEnable', 'TF 状态', enabled == null || enabled === '' ? null : enabled === true ? '已启用' : enabled === false ? '未启用' : String(enabled) + '（设备原始值）'),
    field('storageTotal', 'TF 总量', rawStorage(total)),
    field('storageUsed', 'TF 已用', rawStorage(device?.storageUsed)),
    field('storageAvailable', 'TF 可用', rawStorage(free)),
  ];
  const pressureValue = pressure == null ? '未上报' : `${pressure}（单位未提供）`;
  const altitude = number(device?.barometricAltitude, -Infinity);
  const temperature = number(device?.temperature, -Infinity);
  const fields = [
    { ...field('pressure', '气压', pressureValue), reportedAt: pressureAt, status: ageLabel(pressureAt, device?.pressureFreshness ?? device?.baroFreshness) },
    field('barometricAltitude', '气压海拔', altitude == null ? null : `${altitude} m`),
    field('temperature', '设备温度', temperature == null ? null : `${temperature}（单位未提供）`),
    ...storageFields,
  ];
  return {
    fields, storageFields,
    pressure: pressureValue, pressureAt,
    pressureStatus: ageLabel(pressureAt, device?.pressureFreshness ?? device?.baroFreshness),
    storage: device?.tfEnable === false ? 'TF 未启用' : total == null && free == null ? '未上报' : `总量 ${total ?? '未知'} / 可用 ${free ?? '未知'}${tf.unit || device?.tfUnit ? ' ' + (tf.unit || device.tfUnit) : '（设备原始单位）'}`,
    storageAt: tfAt, storageStatus: ageLabel(tfAt, device?.storageAvailableFreshness ?? device?.storageTotalFreshness ?? device?.tfFreshness ?? device?.storageFreshness),
  };
}
export function splitRecordingParameters(durationSeconds, watermark) {
  const duration = Number(durationSeconds);
  if (!Number.isInteger(duration) || duration < 1 || duration > 86400) throw Error('录像时长须为 1 至 86400 秒的整数');
  return { durationSeconds: duration, ...splitWatermarkParameters(watermark) };
}
export function splitWatermarkParameters(watermark) {
  const text = String(watermark ?? '').trim();
  if (text.length > 512) throw Error('水印最多 512 字');
  return text ? { watermark: text } : {};
}
