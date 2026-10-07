import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/api.dart';
import 'package:rolling_intelligence_headband/wear/communications/lab_video_stream.dart';

void main() {
  test('video URI uses main API origin and contains no credentials', () {
    final api = WearApi(dio: Dio(BaseOptions(baseUrl: 'http://main-backend:18084')),
      token: () => 'secret', siteId: () => '1', epoch: () => 0);
    final uri = labVideoUri(api, 'call-id', '7');
    expect(uri.toString(), 'http://main-backend:18084/api/v1/lab/calls/call-id/video/stream?deviceId=7');
    expect(uri.toString(), isNot(contains('secret')));
    expect(uri.queryParameters.keys, ['deviceId']);
  });
}
