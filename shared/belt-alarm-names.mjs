// ca_sos type dictionary: 对接设备端接口文档250916.pdf, p.16.
// These are reported event names, not declarations of device capabilities.
export const BELT_ALARM_NAMES = Object.freeze({
  '2': '离开工作区域告警', '3': '温度告警', '4': '跌落（撞击）告警',
  '5': '进入禁区告警', '6': '静默告警', '7': 'SOS 告警',
  '11': '近电告警', '12': '登高告警',
  '17': '进入蓝牙信标告警', '18': '离开蓝牙信标告警',
});

export function beltAlarmTitle(event) {
  const title = event?.title;
  if (event?.protocol !== 'direct-belt' || typeof title !== 'string') return title;
  const generic = /^安全带告警(?:[（(]([^）)]+)[）)])?$/.exec(title);
  if (!generic) return title; // Keep specific names captured from device configuration.
  const code = String(event.rawAlarmType ?? generic[1] ?? '').trim();
  if (generic[1] != null && generic[1] !== code) return title;
  return BELT_ALARM_NAMES[code] || title;
}
