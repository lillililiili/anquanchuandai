import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/events/event_photos.dart';
import 'png_fixture.dart';
import 'wear_session_test.dart' show transport, reply, MemoryCredentials;

WearSession sessionFor(String base) {
  final dio = transport(
    (request) => reply({
      'events': [
        {'id': 'event-one', 'version': 1},
        {'id': 'event-two', 'version': 1},
      ],
      'media': [
        {'eventId': 'event-one', 'blobId': 'upload-one'},
        {'eventId': 'event-two', 'blobId': 'upload-two'},
      ],
    }, raw: true),
  );
  dio.options.baseUrl = base;
  return WearSession(dio: dio, mock: false, credentials: MemoryCredentials())
    ..siteId = 'site-1'
    ..token = 'fixture-token';
}

Widget app(WearSession session, Widget child) => WearScope(
  session: session,
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  final bases = {
    'https://example.invalid': 'https://example.invalid',
    'https://example.invalid/wear-api': 'https://example.invalid/wear-api',
    'https://example.invalid/wear-api/': 'https://example.invalid/wear-api',
    'http://127.0.0.1:18085': 'http://127.0.0.1:18085',
  };
  testWidgets('stored observation photos preserve the configured API prefix', (
    t,
  ) async {
    for (final entry in bases.entries) {
      final session = sessionFor(entry.key);
      await t.pumpWidget(
        app(session, const EventStoredPhotos(blobIds: ['upload-one'])),
      );
      await t.pumpAndSettle();
      final image = t.widget<Image>(find.byType(Image)).image as NetworkImage;
      expect(image.url, '${entry.value}/api/guardian/v1/files/upload-one');
      expect(image.headers!['X-Wearable-Token'], 'fixture-token');
      await t.pumpWidget(const SizedBox.shrink());
      session.dispose();
    }
  });
  testWidgets('submitted photos preserve the configured API prefix', (t) async {
    for (final entry in bases.entries) {
      final session = sessionFor(entry.key);
      await t.pumpWidget(
        app(
          session,
          const EventSubmittedPhotos(eventId: 'event-one', version: 1),
        ),
      );
      await t.pumpAndSettle();
      final image = t.widget<Image>(find.byType(Image)).image as NetworkImage;
      expect(image.url, '${entry.value}/api/guardian/v1/files/upload-one');
      await t.pumpWidget(const SizedBox.shrink());
      session.dispose();
    }
  });
  testWidgets('switching equally versioned events reloads their own photos', (
    t,
  ) async {
    final session = sessionFor('https://example.invalid');
    addTearDown(session.dispose);
    await t.pumpWidget(
      app(
        session,
        const EventSubmittedPhotos(eventId: 'event-one', version: 1),
      ),
    );
    await t.pumpAndSettle();
    await t.pumpWidget(
      app(
        session,
        const EventSubmittedPhotos(eventId: 'event-two', version: 1),
      ),
    );
    await t.pumpAndSettle();
    final image = t.widget<Image>(find.byType(Image)).image as NetworkImage;
    expect(image.url, endsWith('/files/upload-two'));
  });
  test('the shared PNG fixture is decoded by the real Flutter codec', () async {
    final codec = await ui.instantiateImageCodec(validPngFixture());
    try {
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 4);
      expect(frame.image.height, 4);
      frame.image.dispose();
    } finally {
      codec.dispose();
    }
  });
}
