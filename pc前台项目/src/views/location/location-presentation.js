import { validLonLat, beijingTime } from '../../lib/location.js';

export function locationPresentation(db, person) {
  const current = db.locationValid(person.id);
  const location = current ? person : person.lastKnownLocation;
  const known = location && validLonLat(location.longitude, location.latitude);
  if (!known) return { deviceId: '无有效定位设备', summary: '暂无有效当前位置', detail: '等待当前领用设备上报' };
  return {
    deviceId: current ? db.locationDevice(person.id)?.id : location.deviceId || '历史来源待确认',
    summary: `${current ? '当前位置' : '最后已知位置 · 历史'}：${Number(location.longitude).toFixed(6)}, ${Number(location.latitude).toFixed(6)} · ${location.coordinateSystem || '坐标系待核实'}`,
    detail: `${location.locationSource || '定位来源待确认'} · ${beijingTime(location.locationReportedAt)}${current ? '' : ' · 当前离线或位置失效，不绘制为当前位置'}`,
  };
}
