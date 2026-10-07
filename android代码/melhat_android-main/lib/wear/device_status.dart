/// Normalize the business API's 1/0 flags without treating stale telemetry as live.
String devicePresence(Map<String, dynamic> device) {
  final quality = device['connectionQuality']?.toString();
  if (quality != null && quality != 'ok') return 'unknown';
  return switch (device['online']?.toString().toLowerCase()) {
    '1' || 'true' || 'online' => 'online',
    '0' || 'false' || 'offline' => 'offline',
    _ => 'unknown',
  };
}
