import '../core.dart';
import 'controller.dart';
import 'models.dart' hide JsonMap;

class WearCommunicationsGateway implements CommunicationsGateway {
  const WearCommunicationsGateway(this.api);

  final WearApi api;

  @override
  Future<StartedCall> startCall({
    required String deviceId,
    required String kind,
    required bool video,
    required String idempotencyKey,
    String? eventId,
  }) async {
    final data = jsonMap(
      await api.post(
        '/api/v1/calls',
        data: {
          'deviceId': deviceId,
          if (eventId != null && eventId.isNotEmpty) 'eventId': eventId,
          'kind': kind,
          'video': video,
          'idempotencyKey': idempotencyKey,
        },
      ),
    );
    final rawCredentials = data['credentials'];
    return StartedCall(
      CallSession.fromJson(data),
      rawCredentials is Map
          ? RtcCredentials.fromJson(jsonMap(rawCredentials))
          : null,
    );
  }

  @override
  Future<CallSession> callDetails(String callId) async =>
      CallSession.fromJson(jsonMap(await api.get('/api/v1/calls/$callId')));

  @override
  Future<RtcCredentials> credentialsFor(String callId) async =>
      RtcCredentials.fromJson(
        jsonMap(await api.get('/api/v1/calls/$callId/credentials')),
      );

  @override
  Future<CallSession> markJoined(String callId, String uid) async =>
      CallSession.fromJson(
        jsonMap(
          await api.post(
            '/api/v1/calls/$callId/joined',
            data: {'agoraUid': uid},
          ),
        ),
      );

  @override
  Future<CallSession> endCall(String callId) async => CallSession.fromJson(
    jsonMap(await api.post('/api/v1/calls/$callId/end')),
  );

  @override
  Future<List<TtsCommand>> sendTts({
    required List<String> deviceIds,
    required String text,
    required String idempotencyKey,
    String? eventId,
  }) async => jsonList(
    await api.post(
      '/api/v1/commands/tts',
      data: {
        'deviceIds': deviceIds,
        'text': text,
        if (eventId != null && eventId.isNotEmpty) 'eventId': eventId,
        'idempotencyKey': idempotencyKey,
      },
    ),
  ).map(TtsCommand.fromJson).toList(growable: false);

  Future<List<PersonOption>> peopleOptions({String? name}) async {
    final query = name == null || name.trim().isEmpty
        ? null
        : {'name': name.trim()};
    return jsonList(
      await api.get('/api/v1/people/options', query: query),
    ).map(PersonOption.fromJson).toList(growable: false);
  }

  Future<List<CommunicationDevice>> listDevices({String? sn}) async {
    try {
      final page = await api.page(
        '/api/v1/devices',
        size: 50,
        query: {if (sn != null && sn.trim().isNotEmpty) 'sn': sn.trim()},
      );
      return page.records
          .map(CommunicationDevice.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<List<JsonMap>> meEquipment() async {
    try {
      return jsonList(await api.get('/api/v1/me/equipment'));
    } catch (_) {
      return const [];
    }
  }

  Future<PersonOption> person(String personId) async =>
      PersonOption.fromJson(jsonMap(await api.get('/api/v1/people/$personId')));

  Future<CommunicationDevice> device(
    String deviceId, {
    JsonMap? assignment,
  }) async => CommunicationDevice.fromJson(
    jsonMap(await api.get('/api/v1/devices/$deviceId')),
    assignment: assignment,
  );

  Future<List<CommunicationDevice>> equipmentForPerson(String personId) async {
    final assignments = jsonList(
      await api.get('/api/v1/people/$personId/equipment'),
    );
    return Future.wait(
      assignments.map((assignment) async {
        final deviceId = idOf(assignment['deviceId']);
        if (deviceId.isEmpty) throw const FormatException('人员装备缺少设备编号');
        return device(deviceId, assignment: assignment);
      }),
    );
  }

  Future<JsonMap> event(String eventId) async =>
      jsonMap(await api.get('/api/v1/events/$eventId'));

  Future<List<CallSession>> calls({String? eventId, String? deviceId}) async {
    final path = eventId != null && eventId.isNotEmpty
        ? '/api/v1/events/$eventId/calls'
        : deviceId != null && deviceId.isNotEmpty
        ? '/api/v1/devices/$deviceId/calls'
        : null;
    if (path == null) return const [];
    return jsonList(
      await api.get(path),
    ).map(CallSession.fromJson).toList(growable: false);
  }
}
