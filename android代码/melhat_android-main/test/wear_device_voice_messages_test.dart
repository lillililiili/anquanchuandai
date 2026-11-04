import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/communications/device_voice_messages.dart';
import 'wear_session_test.dart' show MemoryCredentials;

class _Audio extends DeviceMessageAudio {
  _Audio([this.ready]);
  final Completer<void>? ready;
  int starts = 0, closes = 0;
  bool closed = false;
  @override
  bool playing = false;
  @override
  bool failed = false;
  @override
  Duration position = Duration.zero;
  @override
  Duration duration = const Duration(seconds: 12);
  @override
  Future<void> initialize() async {
    await ready?.future;
  }

  @override
  Future<void> play() async {
    if (closed) return;
    starts++;
    playing = true;
    notifyListeners();
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closes++;
    closed = true;
    playing = false;
    super.dispose();
  }
}

JsonMap _message([JsonMap changes = const {}]) => {
  'id': 'message-1',
  'assetId': 'asset-1',
  'operationType': 'deviceVoiceMessage',
  'direction': 'DEVICE_TO_PLATFORM',
  'source': 'DIRECT_HELMET',
  'reportAct': 'ca_sending_message',
  'deviceId': 'helmet-1',
  'personId': 'original-person',
  'personName': '原上报人员',
  'siteId': 'site-1',
  'bindingId': 'original-binding',
  'receivedAt': '2026-10-01T01:02:03Z',
  'timeBasis': 'RECEIVED_AT',
  'status': 'READY',
  'playable': true,
  ...changes,
};

JsonMap _playback([JsonMap changes = const {}]) => {
  'id': 'message-1',
  'assetId': 'asset-1',
  'mime': 'audio/mpeg',
  'url':
      'https://example.invalid/helmet-media/files/asset-1?variant=playback&token=test-only',
  'expiresAt': DateTime.now()
      .toUtc()
      .add(const Duration(seconds: 30))
      .toIso8601String(),
  ...changes,
};

class _Session extends WearSession {
  _Session(Dio dio)
    : super(dio: dio, mock: false, credentials: MemoryCredentials());
  void revoke() {
    me = {...me!, 'permissions': <String>[]};
    notifyListeners();
  }
}

class _Fixture {
  _Fixture({String user = 'user-1', String site = 'site-1'}) {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) async {
          requests.add(request);
          expect(request.method, 'GET');
          final isPlayback = request.path.endsWith('/playback');
          if (isPlayback && playbackGate != null) await playbackGate!.future;
          if (!isPlayback && listGate != null) await listGate!.future;
          final code = isPlayback ? playbackCode : listCode;
          handler.resolve(
            Response(
              requestOptions: request,
              statusCode: code,
              data: code >= 400
                  ? {'code': code, 'message': 'isolated refusal'}
                  : isPlayback
                  ? _playback()
                  : {
                      'rows': rows,
                      'total': total ?? rows.length,
                      'pageNum': request.queryParameters['pageNum'],
                      'pageSize': 5,
                    },
            ),
          );
        },
      ),
    );
    session = _Session(dio)
      ..token = 'isolated-token'
      ..siteId = site
      ..me = {
        'userId': user,
        'personName': '当前人员不作归属',
        'permissions': ['communications:voice'],
      };
  }
  late _Session session;
  final requests = <RequestOptions>[];
  final audios = <_Audio>[];
  List<JsonMap> rows = [_message()];
  int listCode = 200, playbackCode = 200;
  int? total;
  Completer<void>? playbackGate, initializeGate, listGate;
  DateTime? clock;

  Widget widget({bool active = true, double textScale = 1}) => WearScope(
    session: session,
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: TickerMode(
          enabled: active,
          child: SingleChildScrollView(
            child: DeviceVoiceMessages(
              now: () => clock ?? DateTime.now(),
              createAudio: (_) {
                final audio = _Audio(initializeGate);
                audios.add(audio);
                return audio;
              },
            ),
          ),
        ),
      ),
    ),
  );
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(widget());
    await tester.pumpAndSettle();
    await tester.tap(find.text('设备语音消息（非实时通话）'));
    await tester.pumpAndSettle();
  }

  Future<void> play(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey('voice-message-play-message-1')),
    );
    await tester.pumpAndSettle();
  }

  void dispose() => session.dispose();
}

void main() {
  test(
    'playback requires matching message asset MP3 variant and unexpired HTTPS ticket',
    () {
      expect(deviceMessagePlaybackUri(_message(), _playback()), isNotNull);
      for (final changes in <JsonMap>[
        {'id': 'other'},
        {'assetId': 'other'},
        {'mime': 'audio/amr'},
        {'expiresAt': '2000-01-01T00:00:00Z'},
        {'expiresAt': '2099-01-01T00:00:00'},
        {
          'url':
              'http://example.invalid/helmet-media/files/asset-1?variant=playback&token=t',
        },
        {
          'url':
              'https://account:password@example.invalid/helmet-media/files/asset-1?variant=playback&token=t',
        },
        {
          'url':
              'https://example.invalid/helmet-media/files/other?variant=playback&token=t',
        },
        {'url': 'https://example.invalid/helmet-media/files/asset-1?token=t'},
        {
          'url':
              'https://example.invalid/helmet-media/files/asset-1?variant=playback',
        },
        {
          'url':
              'https://example.invalid/helmet-media/files/asset-1?variant=playback&token=t&token=other',
        },
        {
          'url':
              'https://example.invalid/helmet-media/files/asset-1?variant=playback&variant=playback&token=t',
        },
      ]) {
        expect(
          deviceMessagePlaybackUri(_message(), _playback(changes)),
          isNull,
        );
      }
      for (final changes in <JsonMap>[
        {'source': 'DIRECT_BELT'},
        {'reportAct': 'ca_sos'},
        {'status': 'REJECTED'},
        {'operationType': 'call'},
        {'playable': false},
        {'timeBasis': 'DEVICE_TIME'},
      ]) {
        expect(
          deviceMessagePlaybackUri(_message(changes), _playback()),
          isNull,
        );
      }
    },
  );

  testWidgets(
    'collapsed messages do not fetch, list does not autoplay, explicit play is GET only',
    (tester) async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await tester.pumpWidget(f.widget());
      await tester.pumpAndSettle();
      expect(f.requests, isEmpty);
      expect(f.audios, isEmpty);
      await tester.tap(find.text('设备语音消息（非实时通话）'));
      await tester.pumpAndSettle();
      expect(f.requests, hasLength(1));
      expect(f.audios, isEmpty);
      expect(find.text('上报时人员：原上报人员'), findsOneWidget);
      expect(find.textContaining('当前人员不作归属'), findsNothing);
      expect(f.session.callActive.value, isFalse);
      await f.play(tester);
      expect(
        f.requests.last.path,
        '/api/guardian/v1/voice-messages/message-1/playback',
      );
      expect(f.audios.single.starts, 1);
      expect(f.session.callActive.value, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(f.audios.single.closes, 1);
    },
  );

  for (final code in [403, 404]) {
    testWidgets('list $code stops playback and removes historical links', (
      tester,
    ) async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.open(tester);
      await f.play(tester);
      f.listCode = code;
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(f.audios.single.closes, 1);
      expect(
        find.byKey(const ValueKey('voice-message-play-message-1')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'playback revoked removes record whereas temporary failure allows retry',
    (tester) async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.open(tester);
      f.playbackCode = 503;
      await f.play(tester);
      expect(f.audios, isEmpty);
      expect(
        find.byKey(const ValueKey('voice-message-play-message-1')),
        findsOneWidget,
      );
      f.playbackCode = 403;
      await f.play(tester);
      expect(
        find.byKey(const ValueKey('voice-message-play-message-1')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final change in ['account', 'site']) {
    testWidgets(
      '$change switch releases player and never autoplays next scope',
      (tester) async {
        final f = _Fixture(),
            after = _Fixture(
              user: change == 'account' ? 'user-2' : 'user-1',
              site: change == 'site' ? 'site-2' : 'site-1',
            );
        addTearDown(f.dispose);
        addTearDown(after.dispose);
        await f.open(tester);
        await f.play(tester);
        await tester.pumpWidget(after.widget());
        await tester.pumpAndSettle();
        expect(f.audios.single.closes, 1);
        expect(after.audios, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('in-place permission revocation immediately releases audio', (
    tester,
  ) async {
    final f = _Fixture();
    addTearDown(f.dispose);
    await f.open(tester);
    await f.play(tester);
    f.listCode = 403;
    f.session.revoke();
    await tester.pumpAndSettle();
    expect(f.audios.single.closes, 1);
    expect(
      find.byKey(const ValueKey('voice-message-play-message-1')),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'inactive tab and background stop playback without automatic resume',
    (tester) async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.open(tester);
      await f.play(tester);
      await tester.pumpWidget(f.widget(active: false));
      await tester.pumpAndSettle();
      expect(f.audios.single.closes, 1);
      await tester.pumpWidget(f.widget());
      await tester.pumpAndSettle();
      expect(f.audios, hasLength(1));
      await f.play(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(f.audios.last.closes, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(f.audios, hasLength(2));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('list removal cancels an in-flight playback ticket', (
    tester,
  ) async {
    final f = _Fixture()..playbackGate = Completer<void>();
    addTearDown(f.dispose);
    await f.open(tester);
    await f.play(tester);
    f.rows = [];
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    f.playbackGate!.complete();
    await tester.pumpAndSettle();
    expect(f.audios, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'late playback reply from former account cannot affect the new player',
    (tester) async {
      final before = _Fixture()..playbackGate = Completer<void>();
      final after = _Fixture(user: 'new-user');
      addTearDown(before.dispose);
      addTearDown(after.dispose);
      await before.open(tester);
      await before.play(tester);
      await tester.pumpWidget(after.widget());
      await tester.pumpAndSettle();
      await after.play(tester);
      before.playbackGate!.complete();
      await tester.pumpAndSettle();
      expect(before.audios, isEmpty);
      expect(after.audios.single.playing, isTrue);
      expect(after.audios.single.closes, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('late audio initialization cannot play after panel closes', (
    tester,
  ) async {
    final f = _Fixture()..initializeGate = Completer<void>();
    addTearDown(f.dispose);
    await f.open(tester);
    await f.play(tester);
    expect(f.audios, hasLength(1));
    await tester.tap(find.text('设备语音消息（非实时通话）'));
    await tester.pumpAndSettle();
    f.initializeGate!.complete();
    await tester.pumpAndSettle();
    expect(f.audios.single.starts, 0);
    expect(f.audios.single.closes, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'expired authorization during initialization cannot begin playback',
    (tester) async {
      final f = _Fixture()..initializeGate = Completer<void>();
      addTearDown(f.dispose);
      await f.open(tester);
      await f.play(tester);
      expect(f.audios, hasLength(1));
      f.clock = DateTime.now().add(const Duration(minutes: 1));
      f.initializeGate!.complete();
      await tester.pumpAndSettle();
      expect(f.audios.single.starts, 0);
      expect(f.audios.single.closes, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('a late list response cannot revive a playback-revoked message', (
    tester,
  ) async {
    final f = _Fixture();
    addTearDown(f.dispose);
    await f.open(tester);
    f.listGate = Completer<void>();
    await tester.tap(find.text('刷新消息'));
    await tester.pump();
    f.playbackCode = 403;
    await f.play(tester);
    expect(
      find.byKey(const ValueKey('voice-message-play-message-1')),
      findsNothing,
    );
    f.listGate!.complete();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('voice-message-play-message-1')),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'asset reassociation and real call activity stop message playback',
    (tester) async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.open(tester);
      await f.play(tester);
      f.rows = [
        _message({'assetId': 'other-asset'}),
      ];
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(f.audios.single.closes, 1);
      f.rows = [_message()];
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      await f.play(tester);
      f.session.callActive.value = true;
      await tester.pumpAndSettle();
      expect(f.audios.last.closes, 1);
      final button = tester.widget<TextButton>(
        find.byKey(const ValueKey('voice-message-play-message-1')),
      );
      expect(button.onPressed, isNull);
      f.session.callActive.value = false;
      await tester.pumpAndSettle();
      expect(f.audios, hasLength(2));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'rejected unknown and missing historical names remain explicit with pagination',
    (tester) async {
      final f = _Fixture()
        ..rows = [
          _message({
            'status': 'REJECTED',
            'playable': false,
            'personName': null,
            'receivedAt': '2026-10-01',
          }),
        ]
        ..total = 6;
      addTearDown(f.dispose);
      await f.open(tester);
      expect(find.text('音频未接收'), findsOneWidget);
      expect(find.textContaining('original-person（历史姓名未提供）'), findsOneWidget);
      expect(find.text('平台接收时间：未提供有效时间'), findsOneWidget);
      await tester.tap(find.text('下一页'));
      await tester.pumpAndSettle();
      expect(f.requests.last.queryParameters['pageNum'], 2);
      expect(f.audios, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('message card fits small phone with doubled text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final f = _Fixture();
    addTearDown(f.dispose);
    await tester.pumpWidget(f.widget(textScale: 2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设备语音消息（非实时通话）'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
