/// Mock is explicit and never a fallback for failed backend requests.
abstract final class BackendConfig {
  static const mock = bool.fromEnvironment('WEAR_MOCK', defaultValue: false);
  static const baseUrl = String.fromEnvironment(
    'WEAR_BACKEND_URL', defaultValue: 'http://127.0.0.1:18084',
  );
}
