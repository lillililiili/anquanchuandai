import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ImmersiveUtil {
  static Future<void> init() async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    final sdk = androidInfo.version.sdkInt; // 直接拿到 SDK 数字，比如 33 = Android 13
    // final release = androidInfo.version.release; // Android 版本字符串，比如 "13"

    if (sdk >= 34) {
      // Android 14、15 用 immersiveSticky
      _immersiveSticky();
    } else {
      // Android 13 及以下用透明状态栏+导航栏
      _edgeToEdge();
    }
  }

  /// 透明状态栏 + 导航栏
  static void _edgeToEdge() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top],
    );
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.yellow,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
    );
  }

  /// 自动沉浸式（手势呼出后几秒自动隐藏）
  static void _immersiveSticky() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.yellow,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
    );
  }
}
