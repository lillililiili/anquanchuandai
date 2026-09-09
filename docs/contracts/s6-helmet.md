# S6 安全帽接入契约

版本：S6　依赖：[00-common.md](00-common.md)、[s3-devices.md](s3-devices.md)、[s4-assignment.md](s4-assignment.md)、[s5-events.md](s5-events.md)

真实（或实验室重放的厂商形状）上报进入平台后，更新设备可信状态，并写入 S5 统一事件。旧 `/ext/**` 路径保留。人员来自 **发生时刻领用**，不是 `safety_hat_info.bind_user_id`。客户端不得用定时器猜测在线。通话仍是 S7。

供应商 HMAC 书面协议未到前：回调 **token 必填**；HMAC 仅在配置了 `melhat.callback.hmac-secret` 时启用。

## 1 回调认证

路径：`POST /ext/helmetAlarm`、`/ext/notifyGnss`、`/ext/sosCall`。Spring 匿名，由 `DeviceCallbackAuthFilter` 校验。

| 头 | 何时 |
| --- | --- |
| `X-Melhat-Callback-Token` | 始终必填，与 `melhat.callback.token` 常时间比较 |
| `X-Melhat-Timestamp` | HMAC 开启时：Unix 秒，偏差默认 ±300s |
| `X-Melhat-Nonce` | HMAC 开启时：窗口内唯一 |
| `X-Melhat-Signature` | HMAC-SHA256 hex，签 `timestamp + "\n" + nonce + "\n" + rawBody` |

认证失败 **401**「设备回调未认证」，不建事件。token 未配置则全部拒绝。

## 2 厂商报文（现有形状）

告警 `HelmatAlarm`：`type`（`silent`/`removal`/`fall`/`proximity`）、`helmetSn`、`startTime`、`endTime`（`yyyy-MM-dd HH:mm:ss`）。

GNSS `GnssNotifyParam`：`helmetSn`、`latitude`、`longitude`（WGS84）、`speed`、`altitude`、`timestamp`。

SOS：与 GNSS 相同字段，可无坐标。

映射：

| 入口 | 平台 `type` | 是否建事件 |
| --- | --- | --- |
| `/ext/sosCall` | `sos` | 是 |
| `fall` | `fall` | 是 |
| `silent` `removal` `proximity` | `realtime` | 是 |
| `/ext/notifyGnss` | — | 否，只写样本 |

`source=helmet`。`sourceEventId` = `helmetSn|type|startTime` 或 `helmetSn|sos|timestamp`（无时间则 received 时间）。重复只增加 `repeatCount`。

先写 `wear_ingest_raw` 再应答。未知帽号：`ignored`，HTTP 200，不建事件。设备未分配厂站：同样 ignored。缺坐标不阻断 SOS/告警，`locationQuality=unknown`。

SOS **不**申请声网 token，**不**广播「已接通」。

## 3 设备连接字段

`GET /api/v1/devices` 增加派生字段（不在分页时回写库）：

| 字段 | 含义 |
| --- | --- |
| `lastReportedAt` / `lastTelemetryAt` | 最后一次被采纳的样本发生时间 |
| `connectionQuality` | `unknown`（无上报）/ `ok`（年龄 ≤ `melhat.telemetry.stale-after-seconds`，默认 180）/ `stale` |
| `locationQuality` | 最近样本：`unknown`/`ok`/`stale` |
| `source` | 无样本 `db`；有上报 `live`；种子未上报仍可 `demo: true` |
| `online` | 无上报保持 `null`（不是离线）。有采纳的上报可为 `"1"`。陈旧 **不**改成离线 |

乱序：仅当样本 `occurredAt >= lastTelemetryAt` 才更新设备连接字段。更早样本只归档。

## 4 管理端补充接口

`GET /api/v1/devices/{id}/samples`：最近遥测点（授权厂站）。

`GET /api/v1/devices/{id}/ingest`：接入摘要。列表角色可见 status/time/key；完整 `payload` 仅设备管理员/平台，且不含回调 token。

`POST /api/v1/ingest/replay`（非 prod + demo-mode，写设备权限）：

```json
{ "path": "/ext/sosCall", "payload": { "helmetSn": "MH-DEMO-001", "latitude": "36.1", "longitude": "117.1", "timestamp": "2026-09-09 12:00:00" } }
```

走同一适配器，`demo: true`。生产不加载。

## 5 错误

| 场景 | HTTP | 说明 |
| --- | --- | --- |
| 回调未认证 / HMAC 失败 / nonce 重复 | 401 | 设备回调未认证 |
| 重放无权限或 prod | 403 | 没有权限执行该操作 |
| 设备跨站 | 403 | 同 S3 |
| 重放缺 path/payload | 400 | 服务端 msg |

隐藏按钮 ≠ 已授权。在线状态以服务端 `connectionQuality` 为准。
