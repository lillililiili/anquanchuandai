import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/belt_alarm_names.dart';
import 'package:rolling_intelligence_headband/wear/shared_models.dart';

void main() {
  Map<String, dynamic> alarm(String code) => {
    'protocol': 'direct-belt', 'rawAlarmType': code,
    'title': '安全带告警（$code）', 'type': '设备通信',
    'status': '待认领', 'version': 3,
  };
  test('known codes display names without rewriting raw codes or workflow state', () {
    final source = alarm('6');
    final result = SharedModels({}).event(source);
    expect(result['title'], '静默告警');
    expect(result['alarmName'], '静默告警');
    expect(result['rawAlarmType'], '6');
    expect(result['version'], 3);
    expect(source['title'], '安全带告警（6）');
    expect(beltAlarmTitle(alarm('3')), '温度告警');
    expect(beltAlarmTitle(alarm('4')), '跌落（撞击）告警');
    expect(beltAlarmTitle(alarm('11')), '近电告警');
  });
  test('unknown codes, conflicting evidence and configured titles are preserved', () {
    for (final source in [alarm('77'), {...alarm('6'), 'protocol': 'other'},
      {...alarm('6'), 'rawAlarmType': '3'},
      {...alarm('6'), 'title': '安全带防双解告警（6）'}]) {
      expect(beltAlarmTitle(source), source['title']);
    }
  });
}
