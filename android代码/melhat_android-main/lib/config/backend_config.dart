/// Both API clients use the same directly reachable backend.
/// Override API_BASE_URL when the computer's network address changes.
/// This development address belongs to the current USB network, not adb reverse.
abstract final class BackendConfig {
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.137.74.38:18084',
  );
}
