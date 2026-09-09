# S7 通话与播报契约

版本：S7　依赖：[00-common.md](00-common.md)、[s1-auth.md](s1-auth.md)、[s3-devices.md](s3-devices.md)、[s5-events.md](s5-events.md)

认领成功 **不等于** 接通。通话失败 **不**关闭 SOS。TTS 接口成功 **不等于** 现场已听到。无 `intercom` 能力不得呼叫；无 `video` 不得开视频。厂站与 `X-Site-Id` 同 S1。隐藏按钮 ≠ 已授权。

`melhat.demo-mode` 下不调用厂商；凭证带 `demo: true`，客户端不得当生产接通。

## 1 通话状态

`requesting` → `offered` → `connected` → `ended`  
非终态可 `failed` / `timed_out`。

仅 `connected` 可展示「已接通」。`offered` 为待加入。`offered` 超过 60 秒未 `joined` 变为 `timed_out`。

## 2 权限

| 能力 | 角色 |
| --- | --- |
| 查询会话/指令 | 值班、班组长、复核、只读、设备管理员、平台（授权厂站） |
| 发起通话、joined、结束 | 值班、班组长 |
| TTS | 值班、班组长、设备管理员、平台 |

权限字：`wear:call:list` `wear:call:query` `wear:call:start` `wear:command:tts`。只读写 403。

## 3 接口

`POST /api/v1/calls`  
`{ "deviceId": "1", "eventId": "12", "kind": "sos", "video": false, "idempotencyKey": "..." }`  
`kind`：`single` | `sos`。目标以 deviceId 为准；仅 eventId 时用事件快照设备。无对讲能力 409「该设备不支持通话」。

成功 `data` 含会话与 `credentials`（仅此次与 credentials 接口返回 token）。

`GET /api/v1/calls/{id}` 无 token 明文。  
`GET /api/v1/calls/{id}/credentials` 仅发起人。  
`POST /api/v1/calls/{id}/joined` `{ "agoraUid": "..." }` 成员须匹配。  
`POST /api/v1/calls/{id}/end` 重复 200。  
`GET /api/v1/events/{id}/calls`、`GET /api/v1/devices/{id}/calls`。

凭证：

```json
{
  "agoraAppId": "demo",
  "channelName": "wear-demo-1",
  "agoraUid": "12",
  "agoraToken": "demo-token",
  "expiresAt": "2026-09-09T13:00:00+08:00",
  "demo": true,
  "video": false
}
```

`POST /api/v1/commands/tts`  
`{ "deviceIds": ["1"], "text": "请注意", "eventId": "12", "idempotencyKey": "..." }`  
每设备一行。`status`：`accepted` | `sent` | `failed` | `unknown`。`sent` 不是已听到。

会话对象要点：`id, kind, status, eventId, deviceId, sn, personId, siteId, requesterUserId, channelName, video, demo, connectionQuality, expiresAt, version`。

## 4 错误

| 场景 | HTTP | msg 方向 |
| --- | --- | --- |
| 未登录 | 401 | 未登录或登录已过期 |
| 只读/平台发起通话、跨站 | 403 | 没有权限执行该操作 |
| 无对讲/无 TTS 能力 | 409 | 该设备不支持通话 / 该设备不支持播报 |
| 状态不允许 joined | 409 | 当前状态冲突，请刷新后重试 |
| 厂商不可达 | 200 会话 `failed` 或 指令 `failed` | 厂商不可达，通话未建立 |

WebSocket `{ type:"wear.call", callId, status, eventId, demo }` 只通知。列表/详情 HTTP 为真相。
