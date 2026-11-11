import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rolling_intelligence_headband/config/backend_config.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/events/event_photos.dart';
import 'package:rolling_intelligence_headband/wear/shared_backend.dart';
import 'package:dio/dio.dart';
import '../test/png_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('isolated PNG renders in both authenticated attachment views', (
    t,
  ) async {
    expect(BackendConfig.mock, false);
    final base = Uri.parse(BackendConfig.baseUrl);
    expect(base.host, '127.0.0.1');
    expect(base.port, 18085);
    final config = jsonMap(
      jsonDecode(const String.fromEnvironment('WEAR_QA_CONFIG')),
    );
    final member = WearSession(mock: false, credentials: MockCredentialStore());
    final manager = WearSession(
      mock: false,
      credentials: MockCredentialStore(),
    );
    for (final session in [member, manager]) {
      session.api.dio.options.receiveTimeout = const Duration(seconds: 90);
    }
    final account = jsonMap(config['member']);
    String? eventId;
    try {
      await member.login(idOf(account['username']), idOf(account['password']));
      await member.selectSite(idOf(config['siteId']));
      var event = jsonMap(
        await member.api.post(
          '/api/v1/events/manual-sos',
          data: {'requestId': SharedBackend.requestId()},
        ),
      );
      eventId = idOf(event['id']);
      event = jsonMap(
        await member.api.post(
          '/api/v1/events/$eventId/report',
          data: FormData.fromMap({
            'version': event['version'],
            'comment':
                'QA image rendering ${DateTime.now().microsecondsSinceEpoch}',
            'files': [
              MultipartFile.fromBytes(
                validPngFixture(),
                filename: 'qa-valid.png',
              ),
            ],
          }),
        ),
      );
      final media = jsonList(
        await member.api.get('/api/v1/events/$eventId/media'),
      );
      expect(media.length, 1);
      final blobId = idOf(media.single['blobId']);
      expect(blobId, startsWith('upload-'));
      await t.pumpWidget(
        WearScope(
          session: member,
          child: MaterialApp(
            home: Scaffold(
              body: SafeArea(
                child: Column(
                  children: [
                    const Text('实际后端图片显示验证'),
                    EventStoredPhotos(blobIds: [blobId]),
                    EventSubmittedPhotos(
                      eventId: eventId,
                      version: intOf(event['version']),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      bool decoded() {
        final images = t.widgetList<RawImage>(find.byType(RawImage)).toList();
        return images.length == 2 &&
            images.every((w) => w.image?.width == 4 && w.image?.height == 4);
      }

      while (!decoded() && DateTime.now().isBefore(deadline)) {
        await t.pump(const Duration(milliseconds: 200));
      }
      expect(
        decoded(),
        true,
        reason: 'Both views must decode actual authenticated HTTP image bytes',
      );
      expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
      expect(t.takeException(), isNull);
      await binding.convertFlutterSurfaceToImage();
      await t.pump(const Duration(milliseconds: 300));
      await binding.takeScreenshot('authenticated-attachment-rendering');
      binding.reportData = {
        ...?binding.reportData,
        'passedChecks': [
          'Both attachment views decoded the real backend PNG as4x4 pixels',
        ],
        'eventId': eventId,
        'blobId': blobId,
        'captureNames': ['authenticated-attachment-rendering'],
      };
    } finally {
      await t.pumpWidget(const SizedBox.shrink());
      // Close only the event created by this disposable image check.
      if (eventId != null) {
        final admin = jsonMap(config['admin']);
        await manager.login(idOf(admin['username']), idOf(admin['password']));
        await manager.selectSite(idOf(config['siteId']));
        var event = jsonMap(await manager.api.get('/api/v1/events/$eventId'));
        for (final action in [
          'claim',
          'assistance/join',
          'assistance/end',
          'verify',
        ]) {
          event = jsonMap(
            await manager.api.post(
              '/api/v1/events/$eventId/$action',
              data: {
                'version': event['version'],
                if (action == 'verify') ...{
                  'conclusion': '需现场处理',
                  'situation': '隔离图片显示验证结束',
                  'measures': '测试完成，无现场设备操作',
                },
              },
            ),
          );
        }
        expect(event['status'], 'verified');
      }
      await manager.logout();
      await member.logout();
      manager.dispose();
      member.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 6)));
}
