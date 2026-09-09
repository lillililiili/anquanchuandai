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
