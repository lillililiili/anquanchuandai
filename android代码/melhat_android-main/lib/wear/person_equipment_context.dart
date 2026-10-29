import 'data.dart';
import 'device_features.dart';

/// Issuance identity comes from the server, never from inferred online state.
JsonMap equipmentContextForDevice(JsonMap state, String deviceId) {
  final contexts = jsonMap(state['personEquipmentContext']);
  for (final entry in contexts.entries) {
    final person = jsonMap(entry.value);
    final device = jsonList(
      person['devices'],
    ).where((d) => idOf(d['deviceId']) == deviceId).firstOrNull;
    if (device != null) {
      return {
        ...device,
        'personId': person['personId'] ?? entry.key,
        'features': jsonMap(person['features']),
      };
    }
  }
  return {};
}

bool hasEquipmentContext(JsonMap value) =>
    idOf(value['personId']).isNotEmpty &&
    idOf(value['assignmentId']).isNotEmpty &&
    intOf(value['assignmentVersion']) > 0;
JsonMap equipmentIdentity(JsonMap value) => {
  'personId': value['personId'],
  'assignmentId': value['assignmentId'],
  'assignmentVersion': value['assignmentVersion'],
};
bool sameEquipmentContext(JsonMap a, JsonMap b) =>
    hasEquipmentContext(a) &&
    hasEquipmentContext(b) &&
    idOf(a['personId']) == idOf(b['personId']) &&
    idOf(a['assignmentId']) == idOf(b['assignmentId']) &&
    intOf(a['assignmentVersion']) == intOf(b['assignmentVersion']);
JsonMap contextualFeature(JsonMap device, JsonMap context, String feature) {
  final declared = deviceFeature(device, feature).toJson();
  final selected = jsonMap(jsonMap(context['features'])[feature]);
  if (hasEquipmentContext(context) &&
      idOf(selected['deviceId']) == idOf(device['id']) &&
      sameEquipmentContext({
        ...selected,
        'personId': context['personId'],
      }, context)) {
    return {...selected};
  }
  return {
    ...declared,
    'available': false,
    'reason': declared['verified'] != true
        ? declared['reason']
        : hasEquipmentContext(context)
        ? '该人员当前装备不支持此操作'
        : '请先办理人员领用',
  };
}
