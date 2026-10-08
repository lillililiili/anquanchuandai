import 'dart:async';
import 'package:dio/dio.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'wear_session_test.dart' show MemoryCredentials, transport, identity;

JsonMap row({
  String state = 'ringing',
  String user = '12',
  String site = '1',
  bool video = false,
}) => {
  'id': 'call-1',
  'siteId': site,
  'userId': user,
  'state': state,
  'direction': 'incoming',
  'video': video,
  'sos': true,
  'createdAt': DateTime.now().millisecondsSinceEpoch,
  'connectedAt': state == 'connected'
      ? DateTime.now().millisecondsSinceEpoch - 3000
      : null,
  'participants': [
    {'deviceId': 'd1', 'sn': 'RL-H001', 'personId': 'p1', 'state': state},
  ],
};

WearSession sessionWith(
  FutureOr<ResponseBody> Function(RequestOptions) handler,
) => WearSession(credentials: MemoryCredentials(), dio: transport(handler))
  ..initialized = true
  ..me = {
    ...identity(),
    'permissions': [
      'wear:event:list',
      'wear:person:list',
      'wear:device:list',
      'wear:task:list',
      'wear:call:list',
      'wear:call:start',
    ],
  }
  ..token = 'test'
  ..siteId = '1';
