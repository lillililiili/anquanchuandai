# 给 Android 协作者 B 的总交接单

日期：2026-09-09  
对象：Flutter App（仓库 `android代码/melhat_android-main`）  
后端与 PC：本仓库维护。Android 业务由 B 维护，不直接改库、不另做一套设备/事件规则。

本文是 **总入口**。各模块细节以契约和分阶段交接单为准，冲突时以契约为准。

| 材料 | 路径 |
| --- | --- |
| 统一约定 | [docs/contracts/00-common.md](../contracts/00-common.md) |
| 分阶段契约 | `docs/contracts/s1-auth.md` … `s10-location.md`（无 s8：安全带协议未到） |
| 分阶段交接 | `docs/handoffs/S0.md` … `S10.md`（无 S8） |
| Android 开发计划 | [docs/planning/Android端分阶段开发计划.md](../planning/Android端分阶段开发计划.md) |
| 硬件未关闭项 | [hardware-open-questions.md](hardware-open-questions.md) |
| 工具链 | [toolchain.md](toolchain.md) |

后端 PC 软件主路径（S0–S7、S9、S10）已在本机测试库跑通。**安全带没有协议，S8 未做。** 不要把演示带画成真设备。

---

## 1 你负责什么

现场值班/班组长用的 App：登录、选厂站、接警、认领、联系现场、查人/装备/任务/位置。

你 **不** 负责：厂商回调 `/ext/**`、围栏绘制与启用、人员/设备主数据维护、作业任务复杂配置、数据库、生产部署。这些在 PC。

服务端已经算好的结果（在线质量、事件状态、装备检查、主位置）直接展示。客户端不要再猜一遍。

---

## 2 联调环境

| 项 | 值 |
| --- | --- |
| 本机后端 | `http://127.0.0.1:18084` |
| 健康检查 | `GET /actuator/health` → `"status":"UP"` |
| 官方模拟器 | `http://10.0.2.2:18084`（现有 App 默认） |
| 雷电等 | `adb reverse tcp:18084 tcp:18084` 或本机局域网 IP，**不要把某台电脑 IP 写进仓库默认值** |
| 共享联调 | 尚未提供。有了再换 baseUrl，不要改契约 |

登录仍走若依：`POST /login`、`GET /getInfo`、`POST /logout`。本机验证码在 `sys_config` 中关闭；若开启，须带 `code`/`uuid`。

新业务一律 `/api/v1/**`，请求头：

```http
Authorization: Bearer <token>
X-Site-Id: <当前厂站数字ID的字符串>
Content-Type: application/json
```

`X-Site-Id` 必须在授权列表中，否则 403。它覆盖 **本次请求** 的厂站，不自动写回会话。会话当前站用 `PUT /api/v1/me/current-site`。

WebSocket：`ws://<host>:18084/ws/{userId}_2?token=<jwt>`。App 通道后缀是 `_2`（PC 是 `_1`）。`dev` 仍可能匿名连上，**请始终带 token**。通知不是存储；断线用 HTTP 补齐。

---

## 3 测试账号

本机演示种子密码与若依默认相同，**以维护者当面确认为准**，不要写进 App 仓库。

| 账号 | 角色 | 厂站 | App 用途 |
| --- | --- | --- | --- |
| `siteA_duty` | 值班 | A | 主账号：接警、认领、通话、任务、位置 |
| `siteA_team_lead` | 班组长 | A | 认领、通话、确认交接 |
| `siteA_reviewer` | 复核 | A | 高风险关闭；不能认领 |
| `siteA_readonly` | 只读 | A | 能看不能写；认领/通话/建任务/写围栏 403 |
| `siteB_duty` | 值班 | B | 跨站：看不到 A 的人/设备/事件 |
| `wear_admin` | 平台 | A+B | 不能认领、不能发起通话；可 TTS |
| `admin` | 若依超管 | A+B | 不要当现场值班账号 |

不要只用 `admin` 验收。每轮至少跑：值班正常路径、只读 403、B 站跨站 403。

---

## 4 统一约定（必须先改客户端）

见 [00-common.md](../contracts/00-common.md)。要点：

- 成功：`{ "code": 200, "msg": "ok", "data": ... }`。分页在 `data`：`{ records, total, current, size }`。空列表是 `records: []`，不是失败。
- **ID 全是字符串**。不要用 `int`/`num` 接 `personId`/`deviceId`/`eventId`。
- 时间：ISO-8601 带时区，例如 `2026-09-09T18:16:17+08:00`。
- 写操作带数字 `version`。过期 **HTTP 409**，提示「当前状态冲突，请刷新后重试」，不要静默覆盖。
- 401 未登录（含 HTTP 200 + `code:401` 的旧入口）；403 已登录但无权限或跨站；409 冲突。
- 隐藏按钮 ≠ 已授权。服务端会再拦一次。
- `demo: true` 必须打「演示」标记，**不得**当成生产在线、真实接通、真实作业。

现有 App 的 `/hat/**`、统计接口、旧 SOS/围栏页 **不是** 新业务真相。可暂时保留入口，但新模块不要再扩展这些路径。

---

## 5 接口地图（已可联调）

| 模块 | 契约 | 交接 | App 应接 | 不要做 |
| --- | --- | --- | --- | --- |
| 身份 | [s1-auth.md](../contracts/s1-auth.md) | [S1.md](S1.md) | `/login`、`/api/v1/me`、`/sites`、选厂站 | 自己维护厂站列表 |
| 人员 | [s2-people.md](../contracts/s2-people.md) | [S2.md](S2.md) | 列表/详情/选择器 | 用 `/system/user/list` 当现场人员 |
| 设备 | [s3-devices.md](../contracts/s3-devices.md) | [S3.md](S3.md) | 列表/详情、看 `capabilities` | 写死「安全帽一定有视频」 |
| 领还 | [s4-assignment.md](../contracts/s4-assignment.md) | [S4.md](S4.md) | 当前装备、历史 | 现场 App 可不做领用办理（PC） |
| 事件 | [s5-events.md](../contracts/s5-events.md) | [S5.md](S5.md) | 列表、详情、认领、处置、inbox | 旧 SOS 表当真相 |
| 帽状态 | [s6-helmet.md](../contracts/s6-helmet.md) | [S6.md](S6.md) | 读 `connectionQuality`、`source=helmet` 事件 | 调 `/ext/**` |
| 通话/TTS | [s7-call.md](../contracts/s7-call.md) | [S7.md](S7.md) | 申请、joined、挂断、TTS | 认领当接通；TTS 成功当听到 |
| 作业/值班 | [s9-work.md](../contracts/s9-work.md) | [S9.md](S9.md) | 我的任务、装备检查、值班摘要 | 当工作票；无票当违章 |
| 位置/围栏 | [s10-location.md](../contracts/s10-location.md) | [S10.md](S10.md) | 人员位置、轨迹、围栏只读 | 发明楼层；陈旧当违章；画围栏 |

**没有 S8 契约。** 安全带只出现在设备类型 `belt` 和领用槽位。遥测、扣合、位置都是未知。

### 5.1 常用路径速查

```text
GET  /api/v1/me
GET  /api/v1/sites
PUT  /api/v1/me/current-site          { siteId }

GET  /api/v1/people
GET  /api/v1/people/options
GET  /api/v1/people/{id}

GET  /api/v1/devices
GET  /api/v1/devices/{id}
GET  /api/v1/product-models

GET  /api/v1/assignments/current?personId=
GET  /api/v1/people/{id}/assignments
POST /api/v1/assignments              （一般 PC）

GET  /api/v1/events
GET  /api/v1/events/{id}
GET  /api/v1/events/{id}/actions
GET  /api/v1/events/inbox/count
POST /api/v1/events/{id}/claim        { version }
POST /api/v1/events/{id}/handle
POST /api/v1/events/{id}/transfer
POST /api/v1/events/{id}/close
POST /api/v1/events/{id}/reopen
POST /api/v1/events/{id}/ack
POST /api/v1/events/simulate          仅非 prod + demo-mode

POST /api/v1/calls                    { deviceId, eventId?, kind, video? }
GET  /api/v1/calls/{id}
GET  /api/v1/calls/{id}/credentials   仅发起人；含 token
POST /api/v1/calls/{id}/joined        { agoraUid }
POST /api/v1/calls/{id}/end
GET  /api/v1/events/{id}/calls
POST /api/v1/commands/tts             { deviceIds, text }
GET  /api/v1/commands/{id}

GET  /api/v1/work-tasks
GET  /api/v1/work-tasks/mine
GET  /api/v1/work-tasks/{id}
GET  /api/v1/work-tasks/{id}/equipment-check
GET  /api/v1/work-tasks/{id}/events
GET  /api/v1/duty/summary
GET  /api/v1/duty/handovers
POST /api/v1/duty/handovers/{id}/confirm

GET  /api/v1/locations/people
GET  /api/v1/locations/people/{id}
GET  /api/v1/locations/people/{id}/tracks?from&to
GET  /api/v1/fences
GET  /api/v1/fences/{id}
```

实验室重放（**不要做进生产包**）：`POST /api/v1/ingest/replay`，需设备管理员 + 非 prod + demo-mode。

---

## 6 种子数据（A 站）

| 对象 | 标识 | 说明 |
| --- | --- | --- |
| 厂站 A | `SITE-DEMO-A` | 演示厂站A |
| 厂站 B | `SITE-DEMO-B` | 演示厂站B |
| 人员 | `P-DEMO-001` | 演示人员01，已领 A 站帽+带 |
| 摄像帽 | `MH-DEMO-001` | 有 intercom / tts / video / gnss |
| 无视频帽 | `MH-DEMO-NOV-A` | 无 intercom，通话 409，可 TTS |
| 安全带 | `BL-DEMO-001` | 无对讲、无 GNSS；检查结果只能 unknown |
| 围栏 | 东区演示围栏 | 多边形 WGS84，覆盖约 36.12,117.12，`demo: true` |

连接质量：`unknown` / `ok` / `stale`。`online == null` 是未知，**不是离线**。默认 180 秒无新上报为陈旧。不要在客户端用定时器改成 offline。

---

## 7 禁止画成「已经完成」的状态

这些是现场误导，验收时直接打回：

| 错误展示 | 正确做法 |
| --- | --- |
| 演示数据当真实在线 | 有 `demo: true` 就标「演示」 |
| 安全带已扣好 / 已在线 / 已定位 | 一律未知；装备检查 `unknown` |
| 无票 = 违章 | 显示「待核实」，不是违章 |
| 楼层 3 层、室内定位已准 | `floor` 恒 null，`floorSource=unknown` |
| 陈旧点 / 未知点 = 越界违章 | 只展示质量；围栏事件以服务端 `type=geofence` 为准 |
| SOS 入库或认领 = 已接通 | 仅通话 `status=connected` 可标已接通 |
| TTS 接口成功 = 现场已听到 | `heard` 当前恒 false，文案「未确认现场听到」 |
| `offered` = 已接通 | 待加入；60 秒未 joined 服务端变为 `timed_out` |
| 安全帽一定能视频/对讲 | 看型号 `capabilities.actions` |
| 任务结束 = 事件关闭 | 事件保持原状 |
| 隐藏了按钮 = 已授权 | 仍会 403，按契约提示 |

硬件书面协议未到：帽的 HMAC/RTC AppId/回执、带的全部协议、定位精度（H-SITE-02）。本机通话凭证带 `demo: true`，**不调厂商 Headband**。

---

## 8 实时消息

当前会推：

```json
{ "type": "wear.event", "eventId": "1", "siteId": "1", "severity": "high", "demo": true }
```

收到后拉 `GET /api/v1/events/{id}` 或列表 `updatedAfter`。旧消息的版本落后时不要覆盖新状态。

通话 WebSocket `{ type: "wear.call" }` **本轮未推送**。通话以 HTTP 详情为准。任务/围栏也没有单独推送。

---

## 9 建议的 App 改造顺序

不要一次性重写。现有 Flutter 的登录、Dio、地图、声网代码可留，把数据源切到 `/api/v1`。

推荐顺序（与 [Android 计划](../planning/Android端分阶段开发计划.md) 一致）：

1. HTTP 层：分页、字符串 ID、`X-Site-Id`、401/403/409、`demo` 标记  
2. 登录 + `/me` + 选厂站  
3. 事件工作区（现场核心）  
4. 设备/人员只读查询 + 能力入口  
5. 通话 / TTS  
6. 值班摘要与我的任务  
7. 人员位置与轨迹  

围栏绘制、领用办理、人员建档留给 PC。安全带阶段等协议，期间只保证 UI 不撒谎。

---

## 10 联调与缺陷怎么提

跨端问题先分清：接口错、客户端解释错、还是消息没到。提缺陷请带：

1. 账号、`X-Site-Id`、请求路径和方法  
2. HTTP 状态、`code`、`msg`、关键 `data`（不要贴 token）  
3. 期望（引用契约章节）与实际  
4. 是否 `demo: true`

契约变更（改字段名、删状态值）会提前写进对应 `docs/contracts/` 并出交接单。增加字段默认向后兼容。

后端本机验证记录在 `docs/acceptance/S0.md`–`S10.md`。Android 接入后请在你侧补「Android 已接入 / 联合验收」状态，不要和「后端可联调」混成一个「完成」。
