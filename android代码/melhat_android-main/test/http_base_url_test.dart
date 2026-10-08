import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/http/index.dart';

void main() {
  test('legacy helpers no longer point at a backend', () {
    expect(Http.instance.dio.options.baseUrl, 'https://mock.invalid');
  });
}
