# Android 运行与发布说明

## 交付边界

独立分支 `codex/android-wearable`；工作目录 `D:/分体式安全帽代码/.worktrees/android-wearable/android代码/melhat_android-main`。主工作目录及其他开发者的后端/PC 文件保持原状。当前应用版本 `1.3.0+7`。

保留 Flutter/Dio、原 Signals 工程、地图、声网及 CARGO 浅色素材。新平台采用 `lib/wear`，默认 `main()` 进入 `WearApp`。四个主入口为工作台、事件、通讯、我的；旧版源码保留，仅用于显式 debug 比对。

## 开发环境命令

本机为避免原生构建中文路径问题，使用 Android 工程的目录联接 `D:/melhat-runtime/wearable-android`。它指向独立工作目录，不能替换为旧的 `github-android` 联接。

```powershell
Set-Location D:/melhat-runtime/wearable-android
$env:PUB_CACHE='D:/melhat-runtime/pub-cache'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:JAVA_HOME='D:/DevTools/jdk-17.0.20.1+1'
$env:GRADLE_USER_HOME='D:/melhat-runtime/gradle-home'
$env:TEMP='D:/melhat-java-tmp'
$env:TMP='D:/melhat-java-tmp'
$env:JAVA_TOOL_OPTIONS='-Djdk.net.unixdomain.tmpdir=D:/melhat-java-tmp -Djava.io.tmpdir=D:/melhat-java-tmp'
& D:/DevTools/flutter_3.41.3/flutter/bin/flutter.bat pub get
& D:/DevTools/flutter_3.41.3/flutter/bin/flutter.bat test --no-pub
& D:/DevTools/flutter_3.41.3/flutter/bin/flutter.bat build apk --debug --no-pub --dart-define=API_BASE_URL=http://10.0.2.2:18084
```

保留 pubspec.lock 原有依赖版本，新增安全存储和极光依赖，禁止为编译顺手更新全部依赖。开发包同时支持 arm64-v8a/x86_64；当前 release 配置仅 arm64-v8a。HTTP 放行只在 debug 的网络安全配置；release 使用 HTTPS/WSS。

安装后使用当前后端的授权账号。不要把密码或 token 写进脚本、截图、交付说明或 Git。debug 默认连接 `10.0.2.2:18084`，真机需用 `API_BASE_URL` 指定真机可访问的地址。

## 私有配置

以下文件被 Git 忽略，只在本地/受保护 CI 中提供；不要提交真实值。此前源码中的签名明文配置已移除；已有历史泄露风险由密钥持有人决定轮换，不能依赖删除当前源码撤销 Git 历史。

`android/signing.properties`：

```properties
storeFile=/private/location/release.jks
storePassword=YOUR_SECRET
keyAlias=YOUR_ALIAS
keyPassword=YOUR_SECRET
```

`android/push.properties`：

```properties
JPUSH_APPKEY=YOUR_APP_KEY
JPUSH_VENDORS=huawei,xiaomi,vivo
HUAWEI_APPID=YOUR_APP_ID
XIAOMI_APPID=YOUR_APP_ID
XIAOMI_APPKEY=YOUR_APP_KEY
VIVO_APPID=YOUR_APP_ID
VIVO_APPKEY=YOUR_APP_KEY
```

可选厂商名 `huawei,xiaomi,vivo,oppo,honor`，仅填已获批并配置完成的通道。OPPO/HONOR 所需本地 AAR 放 `android/vendor-libs/`；厂商 JSON、包名、证书指纹和后台开关按官方要求配置。该 opt-in 通道配置必须在目标厂商真机独立验证，当前没有提供私有通道配置，不能认定辅助通道已验收。`jpush_flutter 3.5.7` 核心 SDK 为 6.2.0，通道适配依赖按同一版本配置。

## 正式包门禁

```powershell
& D:/DevTools/flutter_3.41.3/flutter/bin/flutter.bat build apk --release --no-pub --dart-define=API_BASE_URL=https://YOUR_AUTHORIZED_HOST
```

`preReleaseBuild` 要求私有签名配置、显式 HTTPS API 地址，并禁止 `LEGACY_DEMO=true`；release 不使用 debug 签名。正式入口强制新平台，不初始化原 AI/旧业务服务。敏感 HTTP 日志关闭，登录 token 存储在原生安全存储中；主动退出清当前账号草稿和旧版凭据，不清其他账号草稿。

上线前固定 Android 分支提交、后端提交、接口契约版本、签名指纹、APK SHA-256、推送配置版本和支持机型清单。以下任一缺失都不应声称生产接警可用：真实推送联合验收、真实声网通话联合验收、角色权限回归、目标厂站 HTTPS/WSS 连通性。

## 本轮改动索引

| 文件/类 | 主要方法 | 作用与变化 |
| --- | --- | --- |
| `lib/main.dart` | `main` | 默认新平台；旧 UI 仅显式 debug 开启 |
| `lib/wear/api.dart` / WearApi | `request/page/invalidate` | 统一响应、分页、ID、厂站头、409/401、旧会话请求取消 |
| `lib/wear/session.dart` / WearSession | `login/selectSite/expire/logout` | 安全凭据、授权厂站、过期重登、通话切站保护、退出数据清理 |
| `lib/wear/app.dart` / WearApp、WearShell | 路由、`_openNotice/_loadCount` | 四导航保留状态、厂站隔离、通知授权路由、待处理数量 |
| `lib/wear/auth_pages.dart` | `_captcha/_submit` | 品牌登录、验证码、加载/失败/重试反馈 |
| `lib/wear/events/` | `EventController`、`EventsPage`、`SharedPreferencesEventStateStore` | 事件闭环、409保稿、同页详情表单、草稿恢复、下一条、人工关联任务 |
| `lib/wear/queries/` | `_load`、`aggregateLostSupervision`、`_loadTracks/_seekTime` | 工作台搜索/图形入口、人员设备历史、失去监护聚合、任务装备检查、轨迹/围栏只读 |
| `lib/wear/communications/` | 通话 start/resume/poll/end、RTC adapter | 服务端状态与本地媒体状态分别确认，演示隔离，TTS不宣称已听到 |
| `lib/wear/notifications.dart` | `start/bind/unbind/receive/_connect` | 极光接入边界、冷启动路由、通知权限、去重、前台 WS/30秒校准 |
| `lib/wear/mine_page.dart` | `_load`、交接确认、退出 | 账号厂站、我的装备、接班权限、连接状态与系统设置 |
| `lib/http/index.dart`、`lib/http/response/response.dart` | 日志配置、`LoginResponse.toString` | 移除敏感请求日志与 token 文本输出 |
| `android/` | Gradle、Manifest、MainActivity | 推送/通知权限、安全网络配置、私有签名、debug/release 区分 |
| `test/wear_*` | 会话、事件、查询、通话、组件测试 | 验证隔离、冲突、草稿、分页、竞态和窄屏大字体 |

具体测试结果、APK 和已知限制记录见同目录 `wearable-implementation.md`；服务端待办见 `backend-handoff.md`。
