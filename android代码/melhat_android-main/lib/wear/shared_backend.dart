import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'api.dart' show WearApiException, StaleSessionException;
import 'data.dart';
import 'shared_models.dart';

typedef SharedTransport =
    Future<dynamic> Function(
      String method,
      String path, {
      Object? data,
      Map<String, dynamic>? query,
      String? contentType,
    });

/// Translates the existing Android view contracts to the shared Spring API.
/// It never supplies example business data or retries ambiguous writes as new operations.
class SharedBackend {
  SharedBackend(this.send, this.siteId, this.epoch);
  final SharedTransport send;
  final String? Function() siteId;
  final int Function() epoch;
  static const root = '/api/guardian/v1';
  JsonMap _identity = {};
  Future<SharedModels>? _reading;
  final Map<String, _Pending> _pending = {};
  final Map<String, Future<dynamic>> _running = {};
  final Map<String, JsonMap> _assignmentCommands = {};
  final Map<String, JsonMap> _communicationCommands = {};

  static String requestId() {
    final random = Random.secure(),
        bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  void invalidate() {
    _reading = null;
    _identity = {};
    _pending.clear();
    _running.clear();
    _assignmentCommands.clear();
    _communicationCommands.clear();
  }

  Future<SharedModels> context() {
    final existing = _reading;
    if (existing != null) return existing;
    final scope = epoch();
    late final Future<SharedModels> future;
    future =
        (() async {
          final data = jsonMap(
            await send(
              'GET',
              '$root/mobile/context',
              query: {'siteId': siteId()},
            ),
          );
          if (scope != epoch()) throw const StaleSessionException();
          _identity = jsonMap(data['operator']);
          return SharedModels(data);
        })().whenComplete(() {
          if (identical(_reading, future)) _reading = null;
        });
    _reading = future;
    return future;
  }

  JsonMap _page(List<JsonMap> rows, JsonMap q) {
    final current = intOf(q['current'], 1).clamp(1, 100000),
        size = intOf(q['size'], 20).clamp(1, 1000);
    return {
      'records': rows.skip((current - 1) * size).take(size).toList(),
      'total': rows.length,
      'current': current,
      'size': size,
    };
  }

  JsonMap _required(JsonMap value) {
    if (value.isEmpty) throw const WearApiException(404, '资料不存在或不在授权范围');
    return value;
  }

  JsonMap _body(Object? data) => data is FormData
      ? {for (final f in data.fields) f.key: f.value}
      : jsonMap(data);
  bool _eventMatches(JsonMap e, JsonMap q) {
    for (final key in [
      'type',
      'personId',
      'taskId',
      'claimantUserId',
      'alarmCode',
      'severity',
    ]) {
      if (idOf(q[key]).isNotEmpty && idOf(q[key]) != idOf(e[key])) return false;
    }
    final status = idOf(q['status']);
    if (status == 'active' || status.isEmpty && idOf(q['statuses']).isEmpty) {
      if (e['status'] == 'verified') return false;
    } else if (status.isNotEmpty && status != 'all' && status != e['status']) {
      return false;
    }
    for (final pair in {
      'statuses': 'status',
      'types': 'type',
      'alarmCodes': 'alarmCode',
      'deviceTypes': 'deviceType',
    }.entries) {
      if (idOf(q[pair.key]).isNotEmpty &&
          !idOf(q[pair.key]).split(',').contains(idOf(e[pair.value]))) {
        return false;
      }
    }
    return q['escalated'] != 'true' || e['type'] == 'sos';
  }

  Future<dynamic> route(
    String method,
    String path, {
    Object? data,
    JsonMap? query,
  }) async {
    final body = _body(data), q = query ?? <String, dynamic>{};
    final write = method != 'GET',
        parts = path.split('/').map(Uri.decodeComponent).toList();
    if (path == '/captchaImage') {
      return {
        'code': 200,
        'captchaEnabled': false,
      }; // Shared login has no captcha protocol.
    }
    if (path == '/login') {
      final result = jsonMap(
        await send(
          'POST',
          '$root/mobile/login',
          data: {'account': body['username'], 'password': body['password']},
        ),
      );
      _identity = jsonMap(result['identity']);
      return {'code': 200, 'token': result['token']};
    }
    if (path == '/logout') {
      await send('POST', '$root/logout');
      invalidate();
      return null;
    }
    if (path == '/api/v1/me' ||
        path == '/api/v1/sites' ||
        path == '/api/v1/me/current-site') {
      _identity = jsonMap(await send('GET', '$root/mobile/identity'));
      var selected = path.endsWith('current-site')
          ? idOf(body['siteId'])
          : siteId();
      if (selected != null &&
          selected.isNotEmpty &&
          !jsonList(_identity['sites']).any((s) => s['id'] == selected)) {
        if (path.endsWith('current-site')) {
          throw const WearApiException(403, '没有该厂站的访问权限');
        }
        selected = null;
      }
      if (path == '/api/v1/sites') return _identity['sites'];
      return SharedModels.identity(_identity, selected);
    }
    if (path == '/api/v1/events/manual-sos') {
      return SharedModels({}).event(
        jsonMap(
          await send(
            'POST',
            '$root/sos',
            data: {
              'siteId': siteId(),
              'requestId': body['requestId'],
              'description': body['description'] ?? '',
              'locationDescription': body['location'] ?? '',
            },
          ),
        ),
      );
    }
    if (path.startsWith('/api/v1/events/') && parts.length > 5 && write) {
      final action = parts.skip(5).join('/');
      const actions = {
        'claim': 'claim',
        'report': 'observations',
        'verification-draft': 'verification-draft',
        'verify': 'verification',
        'assistance/join': 'assist-join',
        'assistance/end': 'assist-end',
      };
      final native = actions[action];
      if (native == null) throw const WearApiException(404, '此操作未开放');
      return _eventCommand(parts[4], native, body, data);
    }
    if (path.startsWith('/api/v1/assignments') && write) {
      return _assignment(path, body);
    }
    if (path == '/api/v1/calls' && write) return _communicate('calls', body);
    if (path.startsWith('/api/v1/calls/')) {
      return send(
        method,
        '$root/mobile/calls/${parts.skip(4).join('/')}',
        data: data,
      );
    }
    if (path == '/api/v1/commands/tts') return _communicate('broadcast', body);
    if (write) throw const WearApiException(403, '此功能为只读，或尚未开放');

    final model = await context();
    final events = model.rows('events').map(model.event).toList()
      ..sort((a, b) {
        int priority(JsonMap e) =>
            e['type'] == 'sos' && e['status'] != 'verified' ? 0 : 1;
        final p = priority(a).compareTo(priority(b));
        return p != 0
            ? p
            : idOf(b['occurredAt']).compareTo(idOf(a['occurredAt']));
      });
    if (path == '/api/v1/duty/summary') {
      return {
        'unclaimed': events.where((e) => e['status'] == 'open').length,
        'myClaimed': events
            .where(
              (e) =>
                  e['claimantUserId'] == _identity['id'] &&
                  e['status'] != 'verified',
            )
            .length,
        'activeTasks': model
            .rows('works')
            .map(model.work)
            .where((w) => w['status'] != 'ended')
            .toList(),
        'recentEvents': events,
        'pendingEvents': events
            .where((e) => e['status'] != 'verified')
            .toList(),
        'peopleCount': model.rows('people').length,
        'deviceCount': model.rows('devices').length,
        'onlineDevices': model
            .rows('devices')
            .map(model.device)
            .where((d) => d['online'] == 1)
            .length,
      };
    }
    if (path == '/api/v1/me/equipment') {
      return model.equipment(idOf(_identity['personId']));
    }
    if (path == '/api/v1/people' || path == '/api/v1/people/options') {
      final people = model
          .rows('people')
          .map(model.person)
          .where(
            (p) =>
                idOf(p['name']).contains(idOf(q['name'])) &&
                (idOf(q['status']).isEmpty || q['status'] == p['status']),
          )
          .toList();
      return path.endsWith('options') ? people : _page(people, q);
    }
    if (path.startsWith('/api/v1/people/')) {
      final p = _required(model.find('people', parts[4]));
      if (parts.length == 5) return model.person(p);
      if (parts.last == 'equipment') return model.equipment(parts[4]);
      if (parts.last == 'assignments') {
        return model
            .rows('assignments')
            .where((a) => a['personId'] == p['ledgerId'])
            .map(model.assignment)
            .toList();
      }
    }
    if (path == '/api/v1/devices') {
      return _page(
        model
            .rows('devices')
            .map(model.device)
            .where(
              (d) =>
                  idOf(d['sn']).contains(idOf(q['sn'])) &&
                  (idOf(q['typeCode']).isEmpty ||
                      q['typeCode'] == d['typeCode']) &&
                  (idOf(q['assetStatus']).isEmpty ||
                      q['assetStatus'] == d['assetStatus']),
            )
            .toList(),
        q,
      );
    }
    if (path.startsWith('/api/v1/devices/')) {
      final d = _required(model.find('devices', parts[4]));
      if (parts.length == 5) return model.device(d);
      if (parts.last == 'assignments') {
        return model
            .rows('assignments')
            .where((a) => a['deviceId'] == d['ledgerId'])
            .map(model.assignment)
            .toList();
      }
      if (parts.last == 'calls') {
        return send('GET', '$root/mobile/calls', query: {'deviceId': parts[4]});
      }
    }
    if (path == '/api/v1/work-tasks' || path == '/api/v1/work-tasks/mine') {
      final pid = idOf(_identity['personId']);
      final works = model
          .rows('works')
          .where(
            (w) =>
                !path.endsWith('/mine') ||
                pid.isNotEmpty &&
                    ((w['members'] as List? ?? []).contains(pid) ||
                        w['leader'] == pid ||
                        w['supervisor'] == pid),
          )
          .map(model.work)
          .where((w) => idOf(q['status']).isEmpty || q['status'] == w['status'])
          .toList();
      return _page(works, q);
    }
    if (path.startsWith('/api/v1/work-tasks/')) {
      final w = _required(model.find('works', parts[4]));
      if (parts.length == 5) return model.work(w);
      if (parts.last == 'events') {
        return events.where((e) => e['taskId'] == parts[4]).toList();
      }
      if (parts.last == 'equipment-check') {
        return [
          for (final pid in w['members'] as List? ?? [])
            for (final a in model.equipment(idOf(pid)))
              {...a, 'result': 'unknown'},
        ];
      }
    }
    if (path == '/api/v1/events') {
      return _page(events.where((e) => _eventMatches(e, q)).toList(), q);
    }
    if (path == '/api/v1/events/inbox/count') {
      return {'count': events.where((e) => e['status'] != 'verified').length};
    }
    if (path == '/api/v1/events/filter-options') {
      return [
        for (final e in {for (final e in events) e['alarmCode']: e}.values)
          {
            'type': e['type'],
            'code': e['alarmCode'],
            'label': e['alarmName'],
            'severity': e['severity'],
          },
      ];
    }
    if (path.startsWith('/api/v1/events/')) {
      final e = _required(model.find('events', parts[4]));
      if (parts.length == 5) return model.event(e);
      if (parts.last == 'actions') {
        return [
          for (final (i, t) in jsonList(e['timeline']).indexed)
            {
              'id': '${e['id']}-$i',
              'action': t['text'],
              'reason': t['text'],
              'actor': t['actorName'] ?? '历史记录',
              'createTime': t['time'],
            },
        ];
      }
      if (parts.last == 'media') {
        return model
            .rows('media')
            .where(
              (m) => m['eventId'] == e['id'] && idOf(m['blobId']).isNotEmpty,
            )
            .map(
              (m) => {
                ...m,
                'url': '$root/files/${Uri.encodeComponent(idOf(m['blobId']))}',
                'mediaType': 'image/jpeg',
              },
            )
            .toList();
      }
      if (parts.last == 'calls') {
        return send('GET', '$root/mobile/calls', query: {'eventId': parts[4]});
      }
    }
    if (path.startsWith('/api/v1/locations/people/')) {
      final p = _required(model.find('people', parts.last));
      return {
        'personId': p['id'],
        'locationQuality': 'unknown',
        'message': '暂无有效实时位置',
      };
    }
    throw const WearApiException(404, '此功能尚未开放');
  }

  Future<dynamic> _eventCommand(
    String id,
    String action,
    JsonMap body,
    Object? data,
  ) async {
    final key = '$id/$action';
    if (_running.containsKey(key)) return _running[key];
    final operation = _writeEvent(key, id, action, body, data);
    _running[key] = operation;
    try {
      return await operation;
    } finally {
      _running.remove(key);
    }
  }

  Future<dynamic> _writeEvent(
    String key,
    String id,
    String action,
    JsonMap input,
    Object? data,
  ) async {
    final files = <({String name, Uint8List bytes})>[];
    if (data is FormData) {
      for (final file in data.files) {
        final bytes = BytesBuilder();
        await for (final chunk in file.value.clone().finalize()) {
          bytes.add(chunk);
          if (bytes.length > 10 * 1024 * 1024) {
            throw const WearApiException(400, '单张照片不能超过10MB');
          }
        }
        final name = file.value.filename ?? '';
        if (!RegExp(r'\.(png|jpe?g)$', caseSensitive: false).hasMatch(name)) {
          throw const WearApiException(400, '仅支持JPG/PNG照片');
        }
        files.add((name: name, bytes: bytes.takeBytes()));
      }
    }
    final fingerprint = jsonEncode([
      input,
      [
        for (final f in files) [f.name, base64Encode(f.bytes)],
      ],
    ]);
    var pending = _pending[key];
    if (pending == null || pending.fingerprint != fingerprint) {
      pending = _Pending(fingerprint, {
        'expectedVersion': intOf(input['version']),
        'requestId': requestId(),
        if (action == 'observations') 'situation': input['comment'],
        if (action.startsWith('verification'))
          ...'conclusion,situation,measures'
              .split(',')
              .asMap()
              .map((_, k) => MapEntry(k, input[k] ?? '')),
      });
      _pending[key] = pending;
    }
    final scope = epoch();
    try {
      for (var i = pending.photos.length; i < files.length; i++) {
        final file = files[i], photo = 'upload-${requestId()}';
        // A failed upload can leave an orphan, but cannot duplicate an event/observation.
        await send(
          'PUT',
          '$root/files/$photo',
          data: Stream.value(file.bytes),
          contentType: file.name.toLowerCase().endsWith('.png')
              ? 'image/png'
              : 'image/jpeg',
        );
        if (scope != epoch()) throw const StaleSessionException();
        pending.photos.add(photo);
      }
      if (pending.photos.isNotEmpty) {
        if (action == 'observations') {
          pending.body['photoIds'] = pending.photos;
        } else if (!pending.body.containsKey('photoIds')) {
          final model = await context();
          pending.body['photoIds'] = [
            ...model
                .rows('media')
                .where(
                  (m) => m['eventId'] == id && m['purpose'] == 'verification',
                )
                .map((m) => m['blobId']),
            ...pending.photos,
          ];
        }
      }
      final result = await send(
        'POST',
        '$root/events/${Uri.encodeComponent(id)}/$action',
        data: pending.body,
      );
      _pending.remove(key);
      return SharedModels({}).event(jsonMap(result));
    } on WearApiException catch (e) {
      if (e.code >= 400 && e.code < 500) _pending.remove(key);
      rethrow;
    }
  }

  Future<dynamic> _assignment(String path, JsonMap input) async {
    final returning = path.endsWith('/return');
    final operation = idOf(input['idempotencyKey']);
    var command = _assignmentCommands[operation];
    if (command == null) {
      final m = await context();
      final a = returning
          ? _required(
              m.find('assignments', Uri.decodeComponent(path.split('/')[4])),
            )
          : <String, dynamic>{};
      final p = _required(
        m.find(
          'people',
          returning ? m.personId(a['personId']) : input['personId'],
        ),
      );
      final d = _required(
        m.find(
          'devices',
          returning ? m.deviceId(a['deviceId']) : input['deviceId'],
        ),
      );
      command = {
        'siteId': siteId(),
        'personId': p['ledgerId'],
        'personVersion': input['personVersion'] ?? p['version'],
        'operationId': operation,
        'acknowledged': true,
        'items': [
          {
            'deviceId': d['ledgerId'],
            'deviceVersion': input['deviceVersion'] ?? d['version'],
            if (returning) ...{
              'assignmentId': a['id'],
              'assignmentVersion': input['assignmentVersion'] ?? a['version'],
              'condition': 'GOOD',
            },
          },
        ],
      };
      _assignmentCommands[operation] = command;
    }
    try {
      final result = await send(
        'POST',
        '$root/mobile/assignments/${returning ? 'return' : 'issue'}',
        data: command,
      );
      _assignmentCommands.remove(operation);
      return result;
    } on WearApiException catch (e) {
      if (e.code >= 400 && e.code < 500) _assignmentCommands.remove(operation);
      rethrow;
    }
  }

  Future<dynamic> _communicate(String action, JsonMap input) async {
    final fingerprint = jsonEncode({...input}..remove('idempotencyKey'));
    final key = '$action:$fingerprint';
    final body = _communicationCommands.putIfAbsent(
      key,
      () => {...input, 'idempotencyKey': requestId()},
    );
    if (_running.containsKey(key)) return _running[key];
    final request = send('POST', '$root/mobile/$action', data: body);
    _running[key] = request;
    try {
      final result = await request;
      _communicationCommands.remove(key);
      return result;
    } on WearApiException catch (e) {
      if ([400, 401, 403, 404].contains(e.code)) {
        _communicationCommands.remove(key);
      }
      rethrow;
    } finally {
      _running.remove(key);
    }
  }
}

class _Pending {
  _Pending(this.fingerprint, this.body);
  final String fingerprint;
  final JsonMap body;
  final List<String> photos = [];
}
