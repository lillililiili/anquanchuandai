import 'package:dio/dio.dart';

import '../wear/core.dart';
import '../wear/mock_backend.dart';

// Keep the preview's public entry points while sharing the offline transport.
typedef PreviewAdapter = MockBackend;

class PreviewCredentials implements CredentialStore {
  String? _token;
  @override
  Future<String?> read() async => _token;
  @override
  Future<void> write(String? token) async => _token = token;
}

WearSession createPreviewSession() => WearSession(
  credentials: PreviewCredentials(),
  dio: Dio(BaseOptions(baseUrl: 'https://mock.invalid'))
    ..httpClientAdapter = MockBackend(),
);
