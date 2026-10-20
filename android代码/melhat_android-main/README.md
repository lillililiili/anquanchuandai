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

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
