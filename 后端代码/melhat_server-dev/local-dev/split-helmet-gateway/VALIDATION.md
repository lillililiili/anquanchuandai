# 分体帽兼容验证记录

## 2026-11-18 监看中对讲

北京时间 15:35 发布到原云端 `39.106.212.138`。云端后端新增同一观看会话的对讲授权，PC 调度台新增监看和麦克风控制。PC 管理后台通过原入口及资源校验。发布前后使用原角色核对，均为 3 名人员、2 台设备、2 条领用记录和 309 条前台告警，关键台账逐条比对一致。云端回执确认本次数据库迁移数为零，业务配置和其他容器通过一致性校验。

| 验证范围 | 结果 |
| --- | --- |
| PC | 363 项测试通过，生产构建通过。浏览器以本地 WebRTC 测试视频源验证先观看、再开启和关闭对讲，共一次播放协商和一次对讲协商。 |
| 后端 | 50 项分体帽相关测试通过，基于线上实际程序包编译的两个改动类通过 210 项候选版本相关回归。两组测试有重叠。 |
| 安卓 | 分体与通讯等相关测试 85 项通过、2 项既有用例跳过。穿戴业务目录及分体测试的 Dart 静态检查通过。原签名的 1.3.1 调试版（versionCode 12，arm64-v8a 和 x86_64）已覆盖安装到原雷电模拟器，原值班账号可打开设备台账。 |

全项目 `flutter analyze --no-pub` 返回 8 条警告、106 条提示和 0 条错误。逐项比对严重程度、文件、规则和条数，均与 11 月 4 日的全项目检查一致。

项目根目录的 `output/monitor-intercom-20261118/` 中保留发布回执截图、测试视频截图、安卓台账截图、接口比对和 APK。服务器版本备份目录为 `/home/admin/wearables-cloud-production-20261105/releases/monitor-intercom-b2eedbaf2a62/`，其中 `receipt.json` 对应本次发布，`deploy.py --rollback` 可恢复上一版本程序和前台入口。

当日原云端已登记一体帽和安全带各一台。真实分体帽的现场图像、双向声音及断线恢复效果待设备接入后验收。

## 2026-11-16 首次接入

验证日期：2026-11-16。使用本地接口桩、H2/SQLite 临时数据库和隔离组件，不向厂家或线上台账发送测试控制。

| 范围 | 结果 |
| --- | --- |
| PC 前台 | 全量 361 项通过；通话定向 48 项、媒体定向 19 项通过；生产构建通过 |
| PC 管理后台 | 39 个测试文件、550 项通过；生产构建通过 |
| SN 回调分流网关 | 8 项通过：分流、暂停、稳定投递标识、顺序重试、重启、磁盘异常及旧端透传 |
| 客户端 API 网关 | 9 项通过，含 SDP 鉴权、路径/方法白名单、文件 Range、私密头隔离 |
| Flutter | 最终 `dart analyze lib/wear test/wear_split_helmet_test.dart` 为 `No issues found`；相关测试跨批次去重 84 项通过、2 项既有实验室测试跳过；最终分体/预览权限定向 15 项通过（包含于上述数量，不重复相加） |
| 安卓构建 | ARM64 + x86_64 调试 APK 构建通过；未验证 32 位 APK |
| Java 后端 | 综合运行 779 项：新增分体及相关回归通过；1 项既有福大推送限时断言首次失败，该类单独重跑 4/4 通过；0 错误，3 项 MySQL 环境测试跳过。最终全模块 `package` 成功 |

PC 日志位于项目根目录 `output/runtime/split-portal-tests.log`、`split-admin-tests.log`、`split-portal-build.log`、`split-admin-build.log`。界面用隔离 SSR/组件验证，包括手动建档身份锁定、遥测独立时间、媒体操作按钮和混合协议群呼拒绝；未通过正式云端创建测试档案。

Flutter 最终分析日志为 `android代码/melhat_android-main/output/split-helmet-analyze.log`。

后端综合日志为 `后端代码/melhat_server-dev/split-tests-final.log`，定向复跑及打包日志为同目录 `split-package.log`。未修改福大推送业务逻辑或该限时断言。最初沙箱禁止回环连接时，接口桩测试出现网络错误；使用允许本机回环连接的执行权限后，网络相关测试恢复通过。

新分体适配器测试 29 项（服务 12、厂家客户端 5、回调 3、会话/文件权限 9）通过；业务桥接 5、建档 4、独立遥测 6、文件持久索引 1、HTTP 错误状态 1 项通过；另在现有领用测试中补了分体帽撤权场景。综合回归同时覆盖既有 SIP、安全带、事件闭环、归属和权限。旧账号重放测试的样例补齐了当前必需的角色绑定，生产角色规则未调整。

后端最终针对分体帽相关场景执行 92 项定向回归，0 失败、0 错误、0 跳过，并完成全模块打包；最终日志为 `后端代码/melhat_server-dev/split-package-final.log`。构建产物：`后端代码/melhat_server-dev/ruoyi-admin/target/fdc-admin.jar`，2026-11-16 15:33:35 生成，108,495,530 字节。包含超过 310 条历史指令后仍保留未结束录像和抓拍任务关联的回归检查。此记录对应代码交付时的验证；后续本地启动记录见项目根目录 `output/runtime/split-preview/`。

实际启动预览时发现 `SplitHelmetClient` 的双构造器需要显式标记注入构造器，已补 `@Autowired`，并新增真实 Spring 容器装配全部 6 个分体组件的回归测试。该装配测试与厂家客户端测试共 6 项通过，重新打包成功，日志 `split-startup-fix.log`；当前 JAR 为 17:00:10 生成、108,495,564 字节。实际服务启动和三端登录结果另见本地预览运行记录。

代码交付时的安卓产物：`android代码/melhat_android-main/build/app/outputs/flutter-apk/app-debug.apk`（项目根目录下）。构建时间 2026-11-16 15:07:39；约 401 MB；包含 `arm64-v8a` 和 `x86_64`。该历史构建的 SHA-256：

```text
C51D9E2B088D4C15393DCC7E54B1FC3D1E5518F827AE2560BCAE0255273D37B2
```

该历史 APK 沿用项目默认真实后端 `https://lingzhiaide.com/wear-api`，代码交付时未安装或改线上配置。它是调试构建；使用新功能前须按接入说明部署对应后端、数据库增量和网关，或重新指定隔离后端地址构建。首次全架构离线构建因本机缺少 32 位 Flutter 引擎缓存未完成，最终验证的是上述两种 64 位架构。

用户随后要求启动三端预览，因此 16:54:28 重新构建了本地预览版：`WEAR_BACKEND_URL=http://127.0.0.1:18085`、`WEAR_MOCK=false`、versionCode 10。`app-debug.apk` 现已由此预览版替换，并另存为项目根目录 `output/runtime/split-preview/app-preview-debug.apk`，401,247,579 字节，SHA-256 `DB51B2D4F20A11EFD3D3C0FE9ADEC2E7563CDEAD3DECBCD8DE59E72ACAF3CE48`。启动详情见该目录的 README 和构建元数据；未修改源码默认云端地址。

17:32:30 按用户要求恢复原有数据视图，安卓再次构建为原云端地址 `https://lingzhiaide.com/wear-api`，versionCode 11、`WEAR_MOCK=false`。当前 `app-debug.apk` 已替换为该云端恢复版，另存于 `output/runtime/cloud-restore-20261116/app-cloud-debug.apk`，401,247,571 字节，SHA-256 `AD594A59A078A1E56FA6D72A940BCC95471F10A463629E8720C21D3D3E308C9E`。已保留数据覆盖安装并恢复原云端值守员会话；PC 代理也恢复原云端，临时本地预览容器已停止且保留数据卷。原测试厂区 3 人、2 台设备、309 条待认领事件经原云端接口验证仍在，未对云端业务数据进行写入或覆盖。

Android 验证使用 `D:/AndroidDev/flutter/bin/cache/dart-sdk/bin/dart.exe` 和同一 SDK 的 `bin/cache/flutter_tools.snapshot`，通过后者运行 `test --no-pub`。测试批次为：

```text
test/wear_split_helmet_test.dart
test/wear_comms_controller_test.dart
test/wear_contact_group_actions_test.dart
test/wear_media_scope_test.dart
test/wear_media_preview_authority_test.dart
test/wear_device_detail_capability_test.dart
test/wear_real_device_projection_test.dart
test/wear_shared_backend_test.dart
```

该批次 75 项通过、2 项跳过，含当时 5 项分体测试；分体测试补为 7 项后，与预览权限 8 项再次通过；另行执行 `wear_sip_routing_test.dart` 和 `wear_helmet_media_test.dart` 共 7 项通过。以上为跨批次去重 84 项，不是同一次全量执行。构建命令为：

```powershell
.\gradlew.bat --offline --console=plain '-Ptarget-platform=android-arm64,android-x64' :app:assembleDebug
```

构建使用项目的 `android` 目录（本机 `D:/AndroidDev/wearable-android/android` 已核实指向此项目）；Gradle 8.14 构建日志在 `D:/AndroidDev/gradle-home/daemon/8.14/daemon-22896.out.log`。Flutter 测试结果保存在本次执行记录中，未单独导出日志文件。

接口桩和构建不代表厂家网络、实际音视频、GNSS、TF 单位或设备按键已验收。正式设备登记、唯一推送地址切换以及实机验收仍按接入清单进行。原参考平台源码、真实设备台账和正式配置未因本次开发而修改。
