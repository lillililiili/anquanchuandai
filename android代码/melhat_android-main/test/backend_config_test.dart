import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/config/backend_config.dart';
import 'package:rolling_intelligence_headband/http/index.dart';
import 'package:rolling_intelligence_headband/wear/api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('mock transport is explicit and legacy client stays isolated', () {
    final api = WearApi(mock:true, token: () => null, siteId: () => null, epoch: () => 0);
    expect(api.dio.options.baseUrl, BackendConfig.baseUrl);
    expect(Http.instance.dio.options.baseUrl, 'https://mock.invalid');
    final uri = Uri.parse(BackendConfig.baseUrl);
    expect(uri.hasAuthority, isTrue);
    expect(uri.scheme, anyOf('http','https'));
    expect(api.isMock, isTrue);
    api.dio.close();
  });
}
