# 安卓本地开发与热重载

当前入口使用本地 Mock，不需要启动后端。先启动雷电模拟器，然后在本项目目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\bin\run-ldplayer.ps1
```

脚本以 Debug 模式运行当前源码。终端保持打开，按 `r` 热重载，按 `R` 热重启，按 `q` 结束调试。修改 Mock 初始数据或初始化代码后使用热重启；修改原生代码或原生插件后重新运行。

终端中按 `d` 可以断开调试并保留应用运行，随后给启动脚本加 `-Attach` 可重新连接仍在运行的 Debug 应用。

多台模拟器同时运行时，用 `adb devices` 查询设备，再给脚本传入 `-DeviceId emulator-5554`（替换为实际设备）。本轮已隐藏联调及视频入口。

下载依赖需要本机代理时，可加 `-ProxyUrl http://127.0.0.1:7897`（替换为实际代理地址）。脚本会同时配置 Flutter 和 Gradle 的当前进程代理；代理地址不写入项目配置。已有 `HTTPS_PROXY` 时自动沿用。

## VS Code

安装 Flutter 扩展，在 VS Code 中打开本项目目录，选择雷电设备和 `Android Mock (hot reload)` 配置，按 F5。项目已配置 `dart.flutterHotReloadOnSave: all`，在编辑器中保存 Dart 文件可触发热重载。外部工具修改文件后可使用调试工具栏的热重载按钮。

## 本机工具位置

本次环境统一放在 `D:\AndroidDev`：`flutter`、`android-sdk`、`gradle-home`、`pub-cache`，开发过程临时文件使用其中的 `temp` 目录。`ANDROID_DEV_HOME` 可指定其他开发工具根目录。Java 复用之前已有的 JDK 17。Flutter、ADB 已加入用户 PATH；旧终端需要重新打开才能读取新的环境变量。

Flutter 固定为 3.47.6（Dart 3.13.5），Android 平台为 API 36。项目锁文件已同步该 Flutter SDK 必需的 5 个间接依赖版本，并在正式项目目录重新通过 16 项 Mock、入口和页面专项测试。Gradle 仍使用项目原有的 8.14，原生插件与主应用统一使用 NDK 28.2.13676358。

`D:\AndroidDev\wearable-android` 是指向本项目的目录联接，用于避免原生编译工具的中文路径问题，修改任一入口都是同一份源码。VS Code 也建议打开此目录。SDK、缓存和联接均不属于 Git 项目。不要递归删除联接内的文件。

2026-10-07：已从 D 盘完成 Debug APK 构建并安装到雷电 `emulator-5554`（Android 14）。登录页正常显示，热重载命令执行成功（约 1.6 秒）。C 盘原工具和缓存副本已清理；为兼容旧路径保留指向 D 盘的目录联接。真实设备语音与后端联调将在后续阶段验收。
