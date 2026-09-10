# 安卓平台实施记录

基线：a6ed499。仅允许修改本安卓工程，后端、PC、数据库、根目录文档只读。

## 客户端实施状态

以下“已实现”是 Android 代码状态，不代表外部硬件和生产验收通过。

| 阶段 | Android 本轮实现 | 剩余联合验收 |
| --- | --- | --- |
| A0/A1 | 新平台 HTTP、身份、授权厂站、安全存储、旧请求失效、正式入口 | 真机 HTTPS/WSS、各角色交叉切换及登录过期 |
| A5 | 同页事件列表/详情/内联处置、转派/复核/重开、人工关联任务、409 保稿、下一条 | PC 同步、现场完整角色组合与真实事件 |
| A2/A3/A4/A6 | 稳定人员 ID、同名编号、帽/带装备、历史领用、能力入口、未知/陈旧/演示标签 | 真实装备质量和安全带协议；无协议保持未知 |
| A7 | 服务端通话轮询、本地/远端 RTC 联合接通门禁、TTS、权限、极光生命周期与冷启动路由 | 真实声网、目标真机后台持续媒体；推送服务接口/厂商配置/锁屏矩阵 |
| A9/A10 | 我的任务/全站作业、工作台统计与失去监护、装备检查、接班确认、轨迹分页/日期/倍速/时间点、只读围栏 | 真实定位与现场围栏；楼层未知不编造 |
| A11 | 自动化回归、开发包构建与模拟器验证、交接和发布门禁 | 正式签名、生产配置、支持机型与生产联合验收 |

安全带真实遥测、楼层定位、组呼、录制、围栏编辑、完整两票、AI、签到保持延期。旧业务源码保留，仅 debug 显式开关可用于比对。

## 本轮验证方式

测试与编译输出位于本工程忽略目录 `build/verification/`，最终结果附在本文末尾。所有业务接口验证使用当前本机后端，未把旧文档的验收记录当作本次结果。

- 当前后端健康接口 HTTP 200；六种示例账号（值班、班组长、复核、只读、平台、B 站值班）完成身份、人员、事件、工作台只读查询，A/B 站返回各自数据。
- 修正后 `/ws/{userId}/2` 完成握手；后端现有鉴权与多连接问题已列入 `backend-handoff.md`，本轮未修改后端。
- 360dp、1.5 倍文字覆盖四个主导航及正式查询入口；事件表单另覆盖键盘、销毁恢复和防重复写入。
- 有状态回归覆盖会话取消、409、权限、草稿清理竞态、通知重试/换账号/首次注册、RTC 取消与慢轮询。

详见 `android-release.md` 的运行、构建、变更索引和发布配置；外部开发者待办见 `backend-handoff.md`。

## 模块协作约定

新代码放 lib/wear，旧页面保留，正式入口不注册旧业务与 AI 工具。

共享 `core.dart` 导出：
- `typedef JsonMap = Map<String, dynamic>`；`jsonMap(value)`、`jsonList(value)`、`textOf(value, [fallback='—'])`、`idOf(value)`、`intOf(value, [fallback=0])`、`formatTime(value)`。
- `WearApi.get(path, {query}) / post(path, {data}) / put(path, {data}) / delete(path)` 返回解包 data；path 使用 `/api/v1/...` 完整接口路径。
- `WearApi.page(path, {query, current=1, size=20})` 返回 `WearPage.records: List<JsonMap>, total, current, size, hasMore`。
- `WearApiException.code/message`；`StaleSessionException` 表示结果来自过期会话，页面不展示其结果。
- `WearSession extends ChangeNotifier`：`api`, `me: JsonMap?`, `userId: String`, `siteId: String?`, `scopeKey: String`, `roles: Set<String>`, `permissions: Set<String>`, `can(permission)`, `hasRole(role)`, `isDuty`, `isReviewer`, `refreshTick: ValueNotifier<int>`, `requestRefresh()`。
- `WearScope.of(context)` 返回当前 WearSession；页面可用 scopeKey 隔离状态。壳层切站后重建子页面。
- `WearColors`：ink/muted/primary/background/line/danger/warning。
- `WearCard({required child, EdgeInsetsGeometry? padding})`, `WearEmpty({required title, String? detail, VoidCallback? onRetry})`, `WearBadge({required text, Color? color})`, `WearPageHeader({required title, String? subtitle, Widget? trailing})`。

主导航 `/workbench`、`/events`、`/communications`、`/me`。次级路由 `/people`、`/people/:id`、`/devices`、`/devices/:id`、`/tracks?personId=`、`/fences`、`/fences/:id`、`/tasks`、`/tasks/:id`。通知通过 `/events?eventId=` 定位，通讯接受 deviceId、personId、eventId、video 参数。

各模块只调用新接口。未知不展示成正常；演示数据明确标注。异步结果必须考虑 mounted 和 scopeKey；不自动重试写请求。

## 2026-09-10 最终自动化结果

- `flutter test --no-pub --machine`：148 项通过，0 失败；日志 `build/verification/flutter-tests-final.jsonl`。
- `dart analyze lib/wear` 加全部 `test/wear_*_test.dart`：No issues found；日志 `build/verification/analyze-final.log`。
- 事件组件测试覆盖内联处置、键盘、1.5 倍文字、页面销毁恢复、真实可见位置点击、防重复写入、成功反馈和清稿。操作区增加就近反馈，避免提示位于屏幕外而用户看不到。
- 独立审查发现的客户端问题已修复并补测：请求期间离页开麦、RTC/服务端连接状态不一致、终态回退、慢轮询饥饿、过期会话通话门禁、草稿退出写回、推送跨账号串行、RID 首次注册等待、失败通知重试、WS 路由/代次/心跳、无唯一通知 ID 的重复校准。
- 修改范围检查：当前改动全部位于本安卓工程。后端和 PC 未改动，未推送远端。

## 开发安装包与模拟器证据

- `flutter build apk --debug --no-pub --dart-define=API_BASE_URL=http://10.0.2.2:18084` 成功；日志 `build/verification/android-build-final.log`。
- APK：`build/app/outputs/flutter-apk/app-debug.apk`，364,558,663 字节，含 arm64-v8a 与 x86_64 调试依赖。
- SHA-256：`334765fbc541b5afc3e1b3be053d6e59c7bef81ceff3d68e7ac88328ebcdd904`。
- Android API 35 的 `LowAltitude_API35` x86_64 模拟器：安装成功，冷启动成功；使用当前后端示例值班账号完成登录，工作台显示真实接口统计（待认领 2、我负责 0、逾期 1、失去监护 1、已领用人员 1、在用装备 2），事件列表返回围栏与 SOS 两条记录，“我的”显示前台连接正常及推送未配置状态。
- 模拟器首次无默认网络，连接其 `AndroidWifi` 后，设备内健康接口 HTTP 200。期间模拟器进程曾退出，重启同一设备后应用安全登录状态恢复并重新加载工作台。该现象记录为模拟器环境限制，未当作真机稳定性通过。
- 图像证据：`build/verification/01-login.png`、`02-workbench.png`、`03-my.png`；界面结构证据包括 `events-ui.xml`、`restored-ui.xml`。未在实机修改示例事件状态；处置与冲突闭环由自动化测试覆盖，现场/PC/真实硬件组合待联合验收。
- 未生成生产签名包；未提供正式签名、生产 HTTPS/WSS 和推送/声网私有配置。未经真机测试的型号不列入已支持机型。当前 APK 是联调开发包，不能作为生产接警发布包。
