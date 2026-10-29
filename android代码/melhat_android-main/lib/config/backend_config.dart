/// Mock is explicit and never a fallback for failed backend requests.
abstract final class BackendConfig {
  static const mock = bool.fromEnvironment('WEAR_MOCK', defaultValue: false);
  // Current development workspace uses the existing authorized test site only.
  static const testSiteMode = bool.fromEnvironment(
    'WEAR_TEST_SITE_MODE',
    defaultValue: true,
  );
  static const baseUrl = String.fromEnvironment(
    'WEAR_BACKEND_URL',
    defaultValue: 'https://lingzhiaide.com/wear-api',
  );
}
