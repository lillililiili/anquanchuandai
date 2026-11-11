import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/app_diagnostics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('rolling/wear');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'diagnostics use native installed version including build overrides',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'appVersion');
        expect(call.arguments, isNull);
        return {'name': '2.4.6-qa', 'code': 109};
      });
      expect(await installedAppVersion(), '2.4.6-qa (109)');
    },
  );

  test('missing native bridge does not fabricate an old version', () async {
    expect(await installedAppVersion(), '版本信息不可用');
  });

  test('native metadata failure preserves diagnostic availability', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'metadata_unavailable');
    });
    expect(await installedAppVersion(), '版本信息不可用');
  });
}
