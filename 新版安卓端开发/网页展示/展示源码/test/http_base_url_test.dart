import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/http/index.dart';

void main() {
  test('Android emulator uses the host gateway API by default', () {
    expect(Http.instance.dio.options.baseUrl, 'http://10.0.2.2:18084');
  });
}
