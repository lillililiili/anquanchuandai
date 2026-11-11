import 'package:flutter/services.dart';

/// Read the installed Android package version, including build-time overrides.
Future<String> installedAppVersion() async {
  try {
    final value = await const MethodChannel(
      'rolling/wear',
    ).invokeMapMethod<String, dynamic>('appVersion');
    final name = value?['name']?.toString().trim() ?? '';
    final code = int.tryParse(value?['code']?.toString() ?? '');
    if (name.isNotEmpty) return code == null ? name : '$name ($code)';
  } on MissingPluginException {
    // Browser previews do not have an installed Android package.
  } on PlatformException {
    // Diagnostics remain available if native metadata cannot be read.
  }
  return '版本信息不可用';
}
