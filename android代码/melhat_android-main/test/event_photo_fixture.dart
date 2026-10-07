import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/events/event_photos.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+afo4AAAAASUVORK5CYII=',
);

class _CameraFile implements File {
  _CameraFile(this.path);
  @override
  final String path;
  Uint8List get bytes => path.endsWith('.mp4')
      ? Uint8List.fromList([
          0,
          0,
          0,
          20,
          102,
          116,
          121,
          112,
          105,
          115,
          111,
          109,
          0,
          0,
          0,
          0,
          105,
          115,
          111,
          109,
        ])
      : _png;
  @override
  Future<Uint8List> readAsBytes() async => bytes;
  @override
  Future<int> length() async => bytes.length;
  @override
  Stream<List<int>> openRead([int? start, int? end]) =>
      Stream.value(bytes.sublist(start ?? 0, end));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _CameraFiles extends IOOverrides {
  @override
  File createFile(String path) =>
      [
        '/test-camera.png',
        '/test-camera-2.png',
        '/test-video.mp4',
      ].contains(path)
      ? _CameraFile(path)
      : super.createFile(path);
}

// Mock only the camera-result file. Multipart, validation and all UI callbacks remain real.
Future<void> attachTestCameraPhoto(
  WidgetTester tester, {
  bool withVideo = false,
}) async {
  final previous = IOOverrides.current;
  IOOverrides.global = _CameraFiles();
  addTearDown(() {
    IOOverrides.global = previous;
  });
  tester.widget<EventPhotoCapture>(find.byType(EventPhotoCapture)).onChanged([
    '/test-camera.png',
    if (withVideo) ...['/test-camera-2.png', '/test-video.mp4'],
  ]);
  await tester.pumpAndSettle();
}
