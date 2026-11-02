import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/communications/media_preparation.dart';
import 'package:rolling_intelligence_headband/wear/communications/rtc_engine.dart';

void main() {
  test('denied microphone never captures media', () async {
    var captures = 0;
    final preparation = RtcMediaPreparation<Object>(
      requestPermission: (_) async => false,
      acquire: (_) async {
        captures++;
        return Object();
      },
      release: (_) async {},
    );
    await expectLater(
      preparation.prepare(video: false),
      throwsA(isA<RtcPermissionDenied>()),
    );
    expect(captures, 0);
    expect(preparation.take(video: false), isNull);
  });

  test(
    'one prepared stream is transferred once, without reacquisition',
    () async {
      final media = Object();
      var captures = 0, releases = 0;
      final preparation = RtcMediaPreparation<Object>(
        requestPermission: (_) async => true,
        acquire: (_) async {
          captures++;
          return media;
        },
        release: (_) async {
          releases++;
        },
      );
      await preparation.prepare(video: false);
      expect(preparation.take(video: true), isNull);
      expect(identical(preparation.take(video: false), media), isTrue);
      expect(preparation.take(video: false), isNull);
      await preparation.cancel();
      expect(captures, 1);
      expect(releases, 0); // Receiver now owns and releases this exact stream.
    },
  );

  test('cancelled permission cannot capture after a late grant', () async {
    final permission = Completer<bool>(), requested = Completer<void>();
    var captures = 0;
    final preparation = RtcMediaPreparation<Object>(
      requestPermission: (_) {
        requested.complete();
        return permission.future;
      },
      acquire: (_) async {
        captures++;
        return Object();
      },
      release: (_) async {},
    );
    final preparing = preparation.prepare(video: false);
    final result = expectLater(
      preparing,
      throwsA(isA<RtcOperationCancelled>()),
    );
    await requested.future;
    await preparation.cancel();
    await result;
    permission.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(captures, 0);
  });

  test(
    'timed-out capture releases a late stream and never leaves prepared media',
    () async {
      final capture = Completer<Object>();
      final media = Object();
      final released = <Object>[];
      final preparation = RtcMediaPreparation<Object>(
        timeout: const Duration(milliseconds: 5),
        requestPermission: (_) async => true,
        acquire: (_) => capture.future,
        release: (stream) async {
          released.add(stream);
        },
      );
      await expectLater(
        preparation.prepare(video: false),
        throwsA(isA<RtcJoinFailure>()),
      );
      capture.complete(media);
      await Future<void>.delayed(Duration.zero);
      expect(released, [media]);
      expect(preparation.take(video: false), isNull);
    },
  );

  test(
    'immediate cancellation cannot restart acquisition after await cleanup',
    () async {
      var permissions = 0;
      final preparation = RtcMediaPreparation<Object>(
        requestPermission: (_) async {
          permissions++;
          return true;
        },
        acquire: (_) async => Object(),
        release: (_) async {},
      );
      final pending = preparation.prepare(video: false);
      final result = expectLater(
        pending,
        throwsA(isA<RtcOperationCancelled>()),
      );
      await preparation.cancel();
      await result;
      expect(permissions, 0);
    },
  );

  test(
    'late cancelled stream cannot replace or release the next preparation',
    () async {
      final first = Completer<Object>(), started = Completer<void>();
      final oldMedia = Object(), newMedia = Object();
      final released = <Object>[];
      var captures = 0;
      final preparation = RtcMediaPreparation<Object>(
        requestPermission: (_) async => true,
        acquire: (_) {
          if (++captures == 1) {
            started.complete();
            return first.future;
          }
          return Future.value(newMedia);
        },
        release: (media) async {
          released.add(media);
        },
      );
      final old = preparation.prepare(video: false);
      final cancelled = expectLater(old, throwsA(isA<RtcOperationCancelled>()));
      await started.future;
      await preparation.prepare(video: false);
      await cancelled;
      first.complete(oldMedia);
      await Future<void>.delayed(Duration.zero);
      expect(released, [oldMedia]);
      expect(identical(preparation.take(video: false), newMedia), isTrue);
    },
  );
}
