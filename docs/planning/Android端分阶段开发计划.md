# Android 端分阶段开发计划（协作者 B）

版本：V1.0　日期：2026-09-09  
适用：Flutter 工程 `android代码/melhat_android-main`  
对接：后端 `/api/v1` 与 [给 B 的总交接单](../handoffs/B-android.md)

后端与 PC 由另一方维护。你只做 Android。两端共用同一套契约和同一份测试库数据。

本计划按 **A0–A11** 编号，与后端 S0–S11 **一一对应**。后端 S0–S7、S9、S10 已可联调；**S8 安全带协议未到，A8 不能做真接入**。不要等「全部后端再开始」——从 A0 即可对着现网接口改。

---

## 1 产品范围

App 是 **现场接警与查询端**，不是 PC 管理端的缩小版。

值班员打开 App 应能回答：有哪些未关闭事件；我能否认领；现场能不能联系上；这个人现在带着什么、位置是否可信；我名下有哪些任务。

不做：围栏多边形绘制、人员/设备主数据维护、复杂建任务、厂商回调、数据库。

现有工程已有登录、Dio（默认 `http://10.0.2.2:18084`）、旧 `/hat/**`、轨迹地图、声网页面。策略是 **保留技术底座，把业务数据源切到 `/api/v1`**，逐步停用旧帽号接口当真相。

---

## 2 阶段总览

| 阶段 | 目标 | 建议工期 | 后端依赖 | 现在能否开工 |
| --- | --- | --- | --- | --- |
| A0 | HTTP/会话基线 | 3–5 日 | S0 约定 | 能 |
| A1 | 登录、厂站、权限展示 | 3–5 日 | S1 | 能 |
| A2 | 现场人员查询 | 3–5 日 | S2 | 能 |
| A3 | 设备与能力入口 | 4–6 日 | S3 | 能 |
| A4 | 当前装备（只读为主） | 3–4 日 | S4 | 能 |
| A5 | 统一事件工作区 | 6–9 日 | S5 | 能（核心） |
| A6 | 帽连接质量与真实事件源 | 3–4 日 | S6 | 能（读接口；真机回归另计） |
| A7 | SOS 联系、单呼、TTS | 7–10 日 | S7 | 能（demo 通道；真 RTC 等协议） |
| A8 | 安全带状态 | 协议到后 7–11 日 | **S8 未做** | **不能做真接入** |
| A9 | 我的任务、值班摘要 | 5–8 日 | S9 | 能 |
| A10 | 人员位置与轨迹 | 4–6 日 | S10 | 能（精度未确认） |
| A11 | 真机跨端回归与发布配合 | 与后端 S11 并行 | S11 未做 | 后端启动 S11 后再联合 |

合计约 **40–60 个你的工作日**（不含 A8 真接入、不含真机硬件等待）。这是规划估算。硬件协议、声网正式 AppId、现场网络另计。

建议里程碑：

- **M-A1 能上班**：A0–A1，登录选厂站，401/403 正确。
- **M-A2 能接警**：A5 为主，A2–A4 只读配套；认领冲突 409。
- **M-A3 能联系**：A6–A7；仅 `connected` 显示已接通；TTS 未确认听到。
- **M-A4 能值班**：A9–A10；任务待核实不是违章；位置带质量。
- **安全带**：A8 单独，协议未到只做「未知」展示，不进里程碑验收。

---

## 3 每个阶段怎么验收

固定五步，和后端计划对齐：

1. 读对应 `docs/contracts/s*.md` 和 `docs/handoffs/S*.md`。
2. 改数据层（API、模型、字符串 ID、分页）。
3. 改页面；权限以服务端为准，隐藏按钮只是体验。
4. 用 `siteA_duty` / `siteA_readonly` / `siteB_duty` 各跑一遍。
5. 记录：Android 已接入 / 仍用旧接口 / 联合验收。三种状态不要合成「完成」。

完成标准：**对着真实测试库的 HTTP 行为展示正确**，不是 Mock 回填成功。`demo: true` 必须可见。

---

## 4 分阶段任务

### A0 工程基线（对 S0）

**目标**：请求层与后端约定一致，旧接口还能暂时登录。

- [ ] A0-01 确认 Flutter 能连本机 18084（模拟器用 `10.0.2.2`，雷电用 reverse 或局域网 IP）。健康检查 `GET /actuator/health`。
- [ ] A0-02 统一解析 `{ code, msg, data }`；分页读 `data.records`。兼容旧入口 HTTP 200 + `code:401`。
- [ ] A0-03 ID 全部 `String`。时间按 ISO-8601 带时区解析。
- [ ] A0-04 请求带 `Authorization: Bearer`；业务请求带 `X-Site-Id`。
- [ ] A0-05 401 清会话回登录；403/409 用契约文案，不要当网络失败。
- [ ] A0-06 WebSocket 握手带 `token`，路径 `{userId}_2`。
- [ ] A0-07 清点现有 `/hat/**`、统计、旧 SOS/围栏调用，列出「本阶段停用当真相」清单，先不断死登录。

**不要**：改后端、把电脑 IP 写进默认 baseUrl、用 bun。

**验收**：登录拿到 token；无 token 调 `/api/v1/me` 按未登录处理；空列表不报错。

---

### A1 登录与厂站（对 S1）

契约：[s1-auth.md](../contracts/s1-auth.md)

- [ ] A1-01 `POST /login`；登录后立刻 `GET /api/v1/me`（不要只信 `/getInfo`）。`user` 无 password。
- [ ] A1-02 展示 `authorizedSites`，选站 `PUT /api/v1/me/current-site`。无厂站给明确空态，不是崩溃。
- [ ] A1-03 权限用 `me.permissions` / 角色：值班可处置，只读不能。
- [ ] A1-04 `siteB_duty` 带 A 站 `X-Site-Id` → 403。
- [ ] A1-05 退出 `POST /logout` 并清本地 token。账号停用后下次请求 401。

**验收**：A/B 两站账号互不可见；只读能进 App。PC 管理功能不必做。

---

### A2 人员（对 S2）

契约：[s2-people.md](../contracts/s2-people.md)

- [ ] A2-01 `GET /api/v1/people` 列表/搜索；详情 `GET /api/v1/people/{id}`。
- [ ] A2-02 选择器只用 `GET /api/v1/people/options`（`selectable=true`）。**禁止** `/system/user/list` 当现场人员。
- [ ] A2-03 人员独立于登录账号：无 `accountUserId` 仍是现场人员。
- [ ] A2-04 过期/停用：历史详情可打开，不能当作新作业人选。
- [ ] A2-05 跨站详情 403。

现场 App **不必**做新增人员/班组（PC）。若入口存在，只读角色须 403 且无写按钮。

---

### A3 设备与能力（对 S3）

契约：[s3-devices.md](../contracts/s3-devices.md)

- [ ] A3-01 `GET /api/v1/devices`、`/{id}`、`/api/v1/product-models`。
- [ ] A3-02 入口完全跟 `capabilities.actions`：无 `video` 无视频，无 `intercom` 无对讲。禁止「安全帽=有摄像头」。
- [ ] A3-03 `online`/`battery`/`lastReportedAt` 为空显示 **未知**，不是离线、不是 0%。
- [ ] A3-04 `demo: true` 标演示。`BL-DEMO-001` 按安全带型号展示，无对讲。
- [ ] A3-05 `MH-DEMO-NOV-A` 无视频入口；`MH-UNASSIGNED` 值班账号不可见。

不要用旧 `hat_number` 当设备主键。SN / `externalCode` 仅展示。

---

### A4 当前装备（对 S4）

契约：[s4-assignment.md](../contracts/s4-assignment.md)

- [ ] A4-01 人员详情：当前有效领用（帽、带可同时有）。
- [ ] A4-02 历史领用只读；归还后历史人员不变。
- [ ] A4-03 同类型槽位：一人一顶帽、一条带。UI 不要暗示还能再领一顶帽。

领用/归还办理默认 PC。App 若做，必须走 `/api/v1/assignments`，带 version/幂等，处理 409。不要写旧帽绑定接口。

---

### A5 统一事件工作区（对 S5）——优先

契约：[s5-events.md](../contracts/s5-events.md)

这是 App 主路径。旧告警页不要当存储真相。

- [ ] A5-01 未关闭列表：`GET /api/v1/events`；筛选 type/status；空列表 200。
- [ ] A5-02 详情 + `GET .../actions` 时间线。人员/设备是 **发生时快照**，换绑不改历史。
- [ ] A5-03 角标 `GET /api/v1/events/inbox/count`。
- [ ] A5-04 认领 `POST .../claim { version }`：成功占有；并发 **409**「已被认领，请刷新」。
- [ ] A5-05 处置 / 转交 / 关闭 / 重开 / 已看见：按状态机。高风险须复核关闭；值班不能关 SOS。
- [ ] A5-06 WebSocket `wear.event` 只刷新；断线用 `updatedAfter` 补。
- [ ] A5-07 `siteA_readonly`、`wear_admin` 认领 403；`siteB_duty` 不见 A 站事件。
- [ ] A5-08 实验室可用 `POST /api/v1/events/simulate` 做页面，**不要进生产包**。

认领成功 **不等于** 通话接通（A7）。`source=simulator` / `demo: true` 标演示。

**验收**：与 PC 操作同一事件，状态、认领人、动作时间线一致。

---

### A6 帽状态展示（对 S6）

契约：[s6-helmet.md](../contracts/s6-helmet.md)

Android **禁止**调用 `/ext/**`（那是设备回调）。

- [ ] A6-01 设备详情展示 `connectionQuality`：未知 / 有效 / 陈旧。不要客户端倒计时改成离线。
- [ ] A6-02 事件 `source=helmet` 显示「设备上报」，与模拟器区分。
- [ ] A6-03 SOS 出现在事件列表 ≠ 已接通。
- [ ] A6-04 有真帽时：SN 与台账一致，上报后 `lastReportedAt` 更新、事件可见。无真帽用实验室数据，保持 `demo` 标记。

---

### A7 通话与播报（对 S7）

契约：[s7-call.md](../contracts/s7-call.md)

可复用现有声网页，但状态机必须跟服务端。

- [ ] A7-01 `POST /api/v1/calls`，目标 `deviceId`。无 `intercom` → 409。成功 `offered`，文案 **待加入**。
- [ ] A7-02 凭证只从 `GET .../credentials` 取，详情接口无 token 明文。`demo: true` 标演示通道。
- [ ] A7-03 本地加入成功后 `POST .../joined { agoraUid }`，uid 必须匹配。仅此后可标 **已接通**。
- [ ] A7-04 `POST .../end` 可重复；切后台/杀进程后再次打开以 HTTP 详情为准，不要本地永远「通话中」。
- [ ] A7-05 `offered` 超 60 秒未加入，服务端下次读取为 `timed_out`。
- [ ] A7-06 TTS：`POST /api/v1/commands/tts`。展示 `accepted/sent/failed/unknown`。`heard` 恒 false → 「未确认现场听到」。
- [ ] A7-07 只读、平台不能发起通话（403）。平台可 TTS。安全带设备无对讲入口。

本机 **不调 Headband**。真机 RTC 等 H-HAT-05/06 书面确认后再切非演示凭证。通话 WS 未推送，轮询或进详情刷新。

---

### A8 安全带（对 S8）——阻塞

**现状：没有安全带协议，后端未做 BeltAdapter。**

现在允许做、且必须做的只有展示约束：

- [ ] A8-00 凡安全带：连接、扣合、位置、装备检查不得标正常/已扣好/已定位。结果用服务端 `unknown` / `missing`。
- [ ] A8-00b 人员同时持帽和带时，位置只用来自帽的主位置（A10），不要把带当成第二定位源。

协议到达且后端发布 S8 之后再开：

- [ ] A8-01 按型号能力展示带的真实属性/事件。
- [ ] A8-02 带为事件来源时，联系通道再查当前合法设备（通常是同人的帽）。
- [ ] A8-03 网关在线但子设备离线：子设备质量独立计算，不要跟帽子混成一个「在线」。

没有协议就做模拟成功上报，视为未通过。

---

### A9 作业与值班（对 S9）

契约：[s9-work.md](../contracts/s9-work.md)

- [ ] A9-01 `GET /api/v1/duty/summary`：待认领、我的、已升级、失去监护；**人数 ≠ 设备数** 要能解释。
- [ ] A9-02 `GET /api/v1/work-tasks/mine` 与详情：成员、装备检查、关联事件。
- [ ] A9-03 装备检查：帽可 `ok`；安全带无遥测为 `unknown`，禁止绿勾「已佩戴正常」。
- [ ] A9-04 无票且要求票：`ticketStatus=unverified` → **待核实**，不是违章。
- [ ] A9-05 `taskMatch`：`pending` 要人确认，不要客户端自选一个任务。
- [ ] A9-06 交接：列表只读；接班人 `confirm` 后才算移交。未确认不改责任。
- [ ] A9-07 只读无交接、无新建任务。建任务/改成员默认 PC。

任务结束不关闭事件。不要接旧 `/todo/tasks`。

---

### A10 位置与围栏只读（对 S10）

契约：[s10-location.md](../contracts/s10-location.md)

- [ ] A10-01 `GET /api/v1/locations/people`：质量标签 有效/陈旧/未知。
- [ ] A10-02 详情 + `.../tracks?from&to`。空轨迹 200。跨站 403。
- [ ] A10-03 `floor` 空、`floorSource=unknown`：不编楼层、不画分层。
- [ ] A10-04 `GET /api/v1/fences` 只读展示。绘制/启用/禁用走 PC。
- [ ] A10-05 事件 `type=geofence` 展示 `fenceAction`、`ruleVersion`。不要把陈旧轨迹点本地判成违章。
- [ ] A10-06 坐标系 WGS84。H-SITE-02 精度未确认，UI 不要写「已达作业级精度」。

不要用旧 `/hat/electronic/fence` 或旧轨迹帽号接口当本模块真相。

---

### A11 发布配合（对 S11）

后端 S11 未开始。你提前可做：

- [ ] A11-01 与后端冻结一份 API 版本（契约目录 + 后端提交 SHA）。
- [ ] A11-02 生产包去掉 simulate / ingest/replay 入口。
- [ ] A11-03 真机：弱网、杀进程、token 过期、跨站、只读回归。
- [ ] A11-04 后台接警未经验证前，不得写成「可替代值班台」。
- [ ] A11-05 已知限制清单：无安全带真接入、demo RTC、无楼层、围栏未现场闭合。

---

## 5 与现有 Flutter 代码的关系

| 现有 | 处理 |
| --- | --- |
| `lib/http/index.dart` Dio、Bearer | 保留；补 `X-Site-Id`、分页、`code`、字符串 ID |
| `lib/api/user.dart` `/login` `/getInfo` | 登录保留；业务改 `/api/v1/me` |
| `lib/api/hat.dart` `alarm.dart` `fence.dart` `intercom.dart` `tts.dart` | 新模块停止扩展；逐步换成 `/api/v1/devices|events|calls|locations` |
| `lib/views/rtc_page` 声网 | 保留引擎；接通条件改成服务端 `connected` |
| 地图 / 轨迹组件 | 保留渲染；数据改人员轨迹接口，带质量字段 |
| AI 宠物、签到、旧统计 | 不计入首版现场闭环 |

---

## 6 工期怎么排（建议）

后端已经把接口铺好，你可以按现场价值而不是按后端历史顺序：

| 周次（示意） | 内容 |
| --- | --- |
| 第 1 周 | A0 + A1，打通登录厂站 |
| 第 2–3 周 | A5 事件工作区（可穿插 A2/A3 只读） |
| 第 4 周 | A4 当前装备 + A6 质量展示 |
| 第 5–6 周 | A7 通话 TTS（demo 通道） |
| 第 7 周 | A9 值班与我的任务 |
| 第 8 周 | A10 位置轨迹 |
| 之后 | 真机与 A11；A8 等协议 |

若现场先要「能看位置」，A10 可提前到 A5 之后，但接警仍应先可用。

---

## 7 风险与延期

| 风险 | 影响 | 做法 |
| --- | --- | --- |
| 无安全带协议 | 不能验收多品类真实设备 | A8 只做未知展示；里程碑不包含真带 |
| 无帽 RTC 书面协议 | 不能验收生产接通 | demo 通道可做 UI；正式凭证另开 |
| 定位精度未确认 | 不能宣传作业级定位 | 只展示质量与坐标，不写达标 |
| 旧 `/hat` 与新 API 混用 | 状态互相打架 | 新页面只用 `/api/v1` |
| 把 PC 功能搬进 App | 工期翻倍 | 绘制、主数据、复杂建任务留 PC |

延期时先砍：组呼、录制、分层地图、围栏编辑、AI 助手。不砍：厂站权限、认领 409、接通条件、未知态、demo 标记。
