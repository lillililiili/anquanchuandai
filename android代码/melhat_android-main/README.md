# flutter_demo1

## 雷电模拟器保存后自动热重载

先启动雷电及本机 `18084` 后端，在本项目目录运行：

```powershell
# 已安装并打开当前源码对应的 debug APK：连接后保存 Dart 文件自动刷新。
.\bin\run-ldplayer.ps1 -DeviceId emulator-5554 -Attach -Watch

# 首次安装，或改过原生插件、依赖、Android 配置：重新构建并开启自动刷新。
.\bin\run-ldplayer.ps1 -DeviceId emulator-5554 -Watch
```

需要 Flutter、Android SDK 和 Node.js。脚本沿用现有本机工具路径，自动连接真实后端；
出现 `Ready: saving Dart files...` 后，在任意编辑器（包括 Codex）保存 `lib/`、
本地包 `packages/*/lib/` 的 Dart 文件，或修改已有 `assets/` 素材，会合并短时间内的保存并触发热重载。
编译错误不会自动重启应用；修复后再次保存即可。终端输入 `r` 回车可手动刷新，
`R` 回车可热重启，`q` 回车或 Ctrl+C 断开调试并保留应用。

文字、颜色、布局等 `build()` 中的改动通常可保留页面状态直接生效；
`main()`、`initState()`、静态初始化等改动需要热重启。
原生 Java/Kotlin、插件依赖、权限和 `--dart-define` 配置需要停止调试后重新运行构建命令；
新增素材需先在 `pubspec.yaml` 声明并重新启动调试。热重载不会更新磁盘上的 APK，
需要持久安装版本时仍须重新构建。关闭调试进程、模拟器或重启电脑后，需要重新连接。

A new Flutter project.

## 2026-10-26 业务整理验证

设备入口以 `/api/guardian/v1/mobile/context` 返回的 `featureStates` 为准：不支持则隐藏，支持但未验收则显示“待联调”并禁用。`businessConfig.simulatedWatchVisible` 同时控制模拟手表、绑定、体征与筛选入口。正式构建不开放虚构作业预览；“清理业务缓存”保留登录、未提交草稿和未确认请求的幂等键。

本机已存在的 ASCII junction `D:/AndroidDev/wearable-android` 指向本目录。Flutter 版本的 LSP 长度计算在中文工作目录下会截断消息，验证和构建请在这个 junction 中执行，不需要修改 SDK。

```powershell
# 业务代码与本次测试的定向分析，结果 No issues found。
flutter analyze --no-pub lib/wear test/wear_device_features_test.dart test/wear_production_preview_test.dart test/wear_real_device_projection_test.dart test/wear_belt_telemetry_test.dart test/wear_helmet_media_test.dart test/wear_comms_controller_test.dart test/wear_comms_state_test.dart test/wear_comms_entry_test.dart

# 旧 Android API 契约夹具使用显式 mock 编译开关；实际 SharedBackend 测试自行设置 mock:false。
flutter test --no-pub --dart-define=WEAR_MOCK=true test/wear_device_features_test.dart test/wear_demo_visibility_test.dart test/wear_real_device_projection_test.dart test/wear_comms_controller_test.dart test/wear_comms_state_test.dart test/wear_comms_entry_test.dart test/wear_contact_actions_ui_test.dart test/wear_helmet_media_test.dart test/wear_belt_telemetry_test.dart
flutter test --no-pub --dart-define=WEAR_MOCK=true test/wear_shared_backend_test.dart test/wear_session_test.dart test/wear_current_work_test.dart test/wear_work_reference_test.dart test/wear_event_filter_query_test.dart test/wear_event_filters_layout_test.dart test/wear_queries_test.dart
flutter test --no-pub --dart-define=WEAR_MOCK=false test/wear_production_preview_test.dart

# 模拟器安装包，真实服务、无演示数据；install -r 保留已有登录及应用数据。
flutter build apk --debug --no-pub --target-platform android-x64 --dart-define=WEAR_MOCK=false --dart-define=WEAR_BACKEND_URL=https://lingzhiaide.com/wear-api
adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s emulator-5554 shell am start -n com.rolling.intelligence_headband/.MainActivity
```

上述三组回归分别通过 52、39、1 项。最后的联系人/作业 UI 复核通过 15 项，数据保护复核见 `business-final-data-test.log`。完整分析仍有旧页面及本地插件的既有 lint；本次业务目录定向分析无问题。构建、分析、回归日志保存在本目录的 `business-*.log`，不纳入 Git。安装包版本保持 `com.rolling.intelligence_headband`、`1.3.1 (8)`。

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
