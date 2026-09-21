# S5 统一安全事件契约

版本：S5　依赖：[00-common.md](00-common.md)、[s1-auth.md](s1-auth.md)、[s4-assignment.md](s4-assignment.md)

统一事件是接警与处置的唯一业务记录。旧 `sos_alarm_record` / `real_time_alarm` / 围栏告警表仍给旧页使用，**不是**本契约的存储。厂站与 `X-Site-Id` 同 S1。隐藏按钮 ≠ 已授权。

WebSocket 只通知。列表、详情、`updatedAfter`、`inbox/count` 才是真相。断线后用 HTTP 补齐。

## 1 事件对象

ID 为字符串。时间 ISO-8601 `+08:00`。`demo: true` 不得当作真实接入。

```json
{
  "id": "1",
  "type": "sos",
  "severity": "high",
  "status": "open",
  "occurredAt": "2026-09-09T12:00:00+08:00",
  "receivedAt": "2026-09-09T12:00:01+08:00",
  "personId": "1",
  "personCode": "P-DEMO-001",
  "personName": "演示人员01",
  "deviceId": "1",
  "sn": "MH-DEMO-001",
  "siteId": "1",
  "locationLat": null,
  "locationLng": null,
  "locationQuality": "unknown",
  "claimantUserId": null,
  "repeatCount": 0,
  "escalated": false,
  "demo": true,
  "source": "simulator",
  "sourceEventId": "seed-sos-a",
  "ruleVersion": "s5-1",
  "version": 1
}
```

| 字段 | 说明 |
| --- | --- |
| `type` | `sos` `fall` `impact` `geofence` `realtime` |
| `severity` | 由类型决定：`sos`/`fall`/`impact` → `high`；`geofence`/`realtime` → `low`。客户端不能改 |
| `status` | `open` `claimed` `handling` `pending_review` `closed` |
| `alarmCode` | 核心系统保存的具体告警编码，如 `helmet.fence_exit`、`belt.unhooked`；可空。不是处置状态，也不是来源事件编号 |
| `alarmName` | 发生时的具体告警名称，由来源系统／核心场景数据提供；可空，最长255字符。客户端不按大类或来源编号猜测名称 |
| `alarmDescription` | 发生时的告警说明，可包含后端记录的测量值；可空，最长1000字符 |
| 人员/设备/厂站 | **发生时刻**快照。换绑不改历史。无领用则人员为空，禁止用当前绑定人回填 |
| `locationQuality` | `unknown` / `stale` / `ok`。位置缺失不阻断事件 |
| `source` | `simulator` / `legacy_sos` / `legacy_realtime` / `legacy_fence`；日后 `helmet` |
| `sourceEventId` | 与 `source` 组成业务唯一键。重复入库不新建，只增加 `repeatCount` |

动作时间线项：`id, action, actor, reason, fromStatus, toStatus, createTime`。
`action`：`ack` `claim` `handle` `transfer` `review` `close` `reopen` `escalate`。

## 2 状态机

`open` → `claimed` → `handling` →（高风险）`pending_review` → `closed`

| 动作 | 从 | 到 | 谁 |
| --- | --- | --- | --- |
| 入库 | — | `open` | 服务端 ingest |
| `ack` | 任意 | 不变 | 授权可见用户；只记已读，不占责任人 |
| `claim` | `open` | `claimed` | 值班、班组长 |
| `handle` | `claimed` 或 `handling` | 低风险 `handling`；高风险 `pending_review` | 当前认领人 |
| `transfer` | `claimed` / `handling` | 状态不变，换认领人 | 当前认领人；目标须同站值班或班组长 |
| `close` 低风险 | `handling` | `closed` | 值班、班组长 |
| `close` 高风险 | `pending_review` | `closed` | 复核员；平台/若依 admin 可关但不能认领 |
| `reopen` | `closed` | `open`（清空认领人） | 复核员、平台、admin |
| `escalate` | SOS `open` 超过 5 分钟 | 仍 `open`，`escalated=true`，只一次 | 系统 |

误报 = 关闭原因 `false_alarm`，事件仍在。通信失败或传感器恢复不自动关闭。非法迁移 **409**。

认领使用条件更新：`status='open' AND version=?`。已认领或版本冲突 **409**「已被认领，请刷新」。不存在 **404**。无权限 **403**。

## 3 权限

| 能力 | 角色 |
| --- | --- |
| 列表/详情/时间线/未关闭数 | 值班、班组长、复核、只读、设备管理员、平台管理员（授权厂站） |
| ack、认领、处置、转交 | **值班、班组长** |
| 高风险关闭、重开 | **复核员**；平台/若依 admin 可关，**不能**认领 |
| 模拟器 | 非 prod 且 `melhat.demo-mode`，值班/班组长/平台/admin |

只读写操作 403。跨站 403。设备管理员可看不可认领。平台管理员无值班角色认领 403。

权限字（`/api/v1/me`.permissions）：`wear:event:list` `wear:event:query` `wear:event:claim` `wear:event:review`。

## 4 接口 `/api/v1/events`

分页外壳同 [00-common.md](00-common.md)：`{ records, total, current, size }`。写成功返回对象（含 `id` `version`）。

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/api/v1/events` | `current` `size`；默认未关闭。`type` `status` `personId` `severity` `updatedAfter`。厂站按 `X-Site-Id`/当前站，未选则授权并集 |
| GET | `/api/v1/events/{id}` | 详情+快照。跨站 403 |
| GET | `/api/v1/events/{id}/actions` | 时间线倒序 |
| GET | `/api/v1/events/inbox/count` | 授权范围内未关闭数量 `{ "count": 3 }` |
| POST | `/api/v1/events/{id}/ack` | 看见 |
| POST | `/api/v1/events/{id}/claim` | `{ "version": 1 }` |
| POST | `/api/v1/events/{id}/handle` | `{ "comment": "已联系现场", "version": 2 }` |
| POST | `/api/v1/events/{id}/transfer` | `{ "toUserId": "12", "reason": "交班", "version": 2 }` |
| POST | `/api/v1/events/{id}/close` | `{ "reason": "误报", "version": 3 }` 原因必填 |
| POST | `/api/v1/events/{id}/reopen` | `{ "reason": "需继续跟踪", "version": 4 }` |
| POST | `/api/v1/events/simulate` | 仅测试/demo，见下 |

`updatedAfter` 为 ISO 时间，过滤 `updateTime >= updatedAfter`，用于重连补洞。

### 4.1 模拟器

```http
POST /api/v1/events/simulate
{ "sourceEventId": "sim-1", "type": "sos", "siteId": "1", "deviceId": "1", "occurredAt": null, "lat": null, "lng": null }
```

`source=simulator`，`demo=true`。同一 `sourceEventId` 再提交返回已有事件且 `repeatCount>=1`。生产环境不加载该接口。

## 5 实时通知

入库提交后，向该厂站已连接会话按 userId 定向发送（PC `userId_1`，App `userId_2`）：

```json
{ "type": "wear.event", "eventId": "1", "siteId": "1", "severity": "high", "demo": true }
```

不使用全站广播。客户端收到后应再拉 HTTP。通知失败不影响已入库事件。

## 6 错误

| 场景 | HTTP / code | `msg` 方向 |
| --- | --- | --- |
| 未登录 | 401 | 未登录或登录已过期，请重新登录 |
| 跨站、只读写、平台认领、值班关高风险 | 403 | 没有权限执行该操作 / 高风险须复核后关闭 |
| 已被认领、版本冲突、状态不允许 | 409 | 已被认领，请刷新 / 当前状态冲突，请刷新后重试 |
| 无此事件 | 404 | 访问资源不存在 |
| 缺 version、缺关闭原因、模拟类型非法 | 400 | 使用服务端 `msg` |

## 7 种子（测试库）

- 账号（密码 `admin123`）：`siteA_reviewer`、`siteA_team_lead`，仅厂站 A。
- 事件：`seed-sos-a`（A 站 SOS open，快照 `P-DEMO-001`/`MH-DEMO-001`）、`seed-fence-a`（A 站围栏 open）、`seed-sos-b`（B 站 SOS open）、`seed-closed-a`（A 站已关闭低风险）。均为 `demo: true`。

## 8 事件详情地图（2026-09-21）

`GET /api/v1/events/{id}/map-tiles/{z}/{x}/{y}` 返回标准 `R<String>`，`data` 为 PNG 的 Base64 文本。安卓通过已有 WearApi 携带登录令牌、厂站头及会话失效检查，不直接访问地图服务或模拟设备。

- 每次读取（包括命中缓存）先调用事件现有的 `requireReadable` 校验该事件所属厂站访问权限。无登录 401、无权访问事件 403、事件不存在 404。
- `z` 为 3–19，`x/y` 为 `[0, 2^z)`；非法范围 400。上游失败返回 503，不返回伪造底图。
- 主后端只请求固定 OpenStreetMap 瓦片地址，不接受客户端提供 URL，也不向上游转发业务身份信息。瓦片在 Redis 缓存 7 天；不预取、不离线批量下载。依据 [OSM 瓦片使用政策](https://operations.osmfoundation.org/policies/tiles/)。
- 地图标记使用事件 DTO 的 `locationLat/locationLng`（WGS84 事件快照），显示发生时间与 `locationQuality`，不替换成手机 GPS 或设备最新位置。无有效坐标时显示“暂无有效定位”，保留原有核验能力；`stale` 明确标注“定位已陈旧”。
- 两类事件统一展示现场研判，继续使用原 `handle` 接口及 `comment/version`，高风险/低风险状态流转不变；SOS 的旧详情表单不重复展示。
## 9 事件筛选扩展（2026-09-21）

- `GET /api/v1/events/filter-options` 返回当前授权厂站事件快照中的具体告警选项：`[{code, label}]`。按代码去重，名称缺失时显示代码；不从联调模拟场景伪造生产告警字典。
- `GET /api/v1/events` 新增可选 `alarmCode`（精确匹配）、`deviceTypes`（逗号分隔的 `helmet,belt,watch`，同组 OR）。与状态、人员、作业、厂站权限等其他条件组合后在服务端分页。
- 设备类型通过事件关联设备的产品型号查询，空选择不限制设备；无法关联型号的历史记录仍可在“全部设备”中查看。非法设备类型返回 400，筛选选项同样要求登录及厂站权限。
- Android 保留现有流程大类，同时加载具体告警；筛选保存代码、显示名及设备多选，快捷条件会清除这些限制。输入框由面板内的 `TextFormField` 管理生命周期，避免路由退场动画期间提前销毁输入控制器。

### 内嵌多选（2026-09-21 后续调整，交互已由下节替代）

- 事件及通讯使用同一内嵌筛选组件，不再打开筛选模态路由。点击条件组展开限高复选区，同组 OR、跨组 AND；清除后需应用，收起会放弃尚未应用的修改。
- `GET /api/v1/events` 增加 `statuses`、`types`、`alarmCodes`（逗号分隔）；状态按集合匹配，流程大类和具体告警代码属于同一个 OR 组，再与设备、人员、作业、权限范围组合。旧单值参数继续兼容，复选参数存在时优先使用。
- 状态不选时客户端发送 `status=all`；默认“未关闭”在复选界面展开为待认领、已认领、处置中、待复核。指定 `statuses` 可包含已关闭，不叠加默认未关闭限制。
- Android 保留旧筛选缓存读取能力，新增多选数组和告警名称映射；页面重入保留全部选项，快捷筛选会清除多选条件。

### 直接多选（2026-09-21 最新交互）

- 事件与通讯复用 `InlineFilters`，常用选项直接显示为可勾选标签；不再有总展开入口、模态弹窗或“应用”按钮。选择立即反馈，停止选择 300ms 后合并提交查询；再次点击取消，组内“不限”清空本组，“重置”立即清空所有条件。
- 长选项组横向滚动，箭头可原位展开限高复选区，超过 8 个选项提供搜索。连续选择不会自动折叠，已选条件摘要持续可见。人员、任务和认领人 ID 为可展开的补充条件，输入同样自动生效。
- “未关闭”作为状态便捷组合；点击任一具体状态会替换此组合，具体状态之间可多选。同组 OR、跨组 AND 及服务端权限/分页约束不变。“我负责”“已升级”现在可以与其他条件叠加，不再清空多选。
- 自动查询时保留旧结果和滚动位置并显示加载进度；沿用请求代次保护，过期响应不能覆盖最新结果。通讯查询继续使用主平台人员/设备数据，设备在线判断保持原规则。
