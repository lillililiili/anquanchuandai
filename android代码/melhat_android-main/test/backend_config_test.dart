import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/config/backend_config.dart';
import 'package:rolling_intelligence_headband/http/index.dart';
import 'package:rolling_intelligence_headband/wear/api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('both HTTP clients use the same direct backend address', () {
    final api = WearApi(token: () => null, siteId: () => null, epoch: () => 0);
    expect(api.dio.options.baseUrl, BackendConfig.baseUrl);
    expect(Http.instance.dio.options.baseUrl, BackendConfig.baseUrl);
    final uri = Uri.parse(BackendConfig.baseUrl);
    expect(uri.hasAuthority, isTrue);
    expect(
      ['localhost', '127.0.0.1', '::1', '10.0.2.2'],
      isNot(contains(uri.host)),
      reason: 'A phone/emulator build must reach the server without adb reverse.',
    );
    api.dio.close();
  });
}
