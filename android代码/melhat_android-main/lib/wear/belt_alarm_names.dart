// ca_sos type dictionary: 对接设备端接口文档250916.pdf, page 16.
const beltAlarmNames = <String, String>{
  '2': '离开工作区域告警', '3': '温度告警', '4': '跌落（撞击）告警',
  '5': '进入禁区告警', '6': '静默告警', '7': 'SOS 告警',
  '11': '近电告警', '12': '登高告警',
  '17': '进入蓝牙信标告警', '18': '离开蓝牙信标告警',
};

String? beltAlarmTitle(Map<String, dynamic> event) {
  final title = event['title'] as String?;
  if (event['protocol'] != 'direct-belt' || title == null) return title;
  final generic = RegExp(r'^安全带告警(?:[（(]([^）)]+)[）)])?$').firstMatch(title);
  if (generic == null) return title;
  final code = (event['rawAlarmType'] ?? generic.group(1) ?? '').toString().trim();
  if (generic.group(1) != null && generic.group(1) != code) return title;
  return beltAlarmNames[code] ?? title;
}
