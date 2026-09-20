# Java 跳板接口契约与本轮实测摘要

日期：2026-09-20。本文只记录本轮安卓、Java relay 和本地测试依赖，不要求联调平台回退其他任务新增的管理功能。联调平台目录由另一任务继续维护；对新增字段应保持兼容。

## 1. 调用路径与验证身份

安卓测试构建使用 `API_BASE_URL=http://127.0.0.1:18084`、`CALL_LAB_ENABLED=true`。雷电仅需 `adb reverse tcp:18084 tcp:18084`，不依赖 `5188` 反向映射。

所有本轮安卓状态操作先到 Java `/api/v1/lab/*`，携带业务 Bearer 与 `X-Site-Id`。Java 按白名单、角色及厂站校验，再转发至虚拟安全帽上游；现阶段不是实际厂商设备协议。

`GET /api/v1/lab/bridge-info` 的当前契约：

```json
{
  "code": 200,
  "data": {
    "bridge": "java-business-backend",
    "enabled": true,
    "upstreamType": "virtual-helmet",
    "simulation": true,
    "realMedia": false
  }
}
```

该标识与请求地址共同用于确认 Java 跳板身份。不能以 Node 直连成功代替这条链路的验证；`simulation=true` 也不表示真实音视频可用。

## 2. 安卓与测试依赖的协议

| 路径 | 本轮依赖 |
| --- | --- |
| `GET /api/v1/lab/roster` | 人员、设备、作业及模拟状态，用于列表和筛选；允许平台增加管理字段 |
| `GET /api/v1/lab/state` | 当前账号可见的 `calls`、模拟设备状态、播报及在线值班信息 |
| `GET /api/v1/lab/state?client=console` | 有权限的设备模拟管理状态 / 心跳 |
| `POST /api/v1/lab/presence` | 按现有 `deviceId` 设置模拟在线状态；不能因此悄悄修改真实佩戴绑定 |
| `POST /api/v1/lab/calls` | 统一呼叫，设备呼入不选择联系人；安卓外呼可包含多台安全帽 |
| `POST /api/v1/lab/calls/{id}/accept` | 接听原呼叫；设备模拟传 `deviceId` |
| `POST /api/v1/lab/calls/{id}/reject` | 表示拒绝来电；帽端 UI 通过挂断键触发，不需要第三个硬件按键 |
| `POST /api/v1/lab/calls/{id}/end` | 结束原会话或指定设备参与状态 |
| `POST /api/v1/lab/calls/{id}/video` | `{ "enabled": true/false }`，控制原会话内单向查看安全帽画面的状态 |
| `POST /api/v1/lab/tts`、`/tts/ack` | 文字播报状态及逐设备模拟回执，不能宣称硬件已发声 |

Java 只转发已允许的路径和参数；联调平台新增能力需要双方明确协议并扩展相应白名单，不应让安卓绕开业务后端来补齐。

## 3. 通话数据与状态约定

本轮使用 `id`、`state`、`direction`、`userId`、`createdAt`、`connectedAt`、`videoEnabled` 和 `participants`。参与者使用 `deviceId`、`state`，人员名称等为展示附加信息。保留其他任务增加的字段，不做全对象等值约束。

- `id` 是一次呼叫的稳定标识。开启 / 关闭单向画面不创建新呼叫。
- `connectedAt` 在首次接听后保持；第二台设备加入、管理员或值班端切换画面均不重置计时。
- 统一呼叫初始 `video=false`、`videoEnabled=false`。启用画面更新 `videoEnabled`，不发送第二次视频邀请，不要求安全帽再次同意。
- 仅已接通参与者可呈现查看中；仍响铃、已拒接、已结束或离线者不能冒充实时画面。
- 挂断、超时或失去所有已接通参与者后应清除画面查看状态。多设备中一个退出，不应结束仍活跃的其他设备。
- 同厂站管理员可代控画面；普通非会话账号和只读账号不得越权。跨厂站请求应拒绝或返回不可见，不能泄露该站通话。

帽端没有屏幕，只有“呼叫 / 接听”共用键与“挂断”键；不能选联系人。摄像头由有权限的值班 / 管理端开启，帽端被动上传。本轮只验证该状态语义，不测试手机摄像头或真实媒体。

## 4. 当前值班路由边界

设备呼入应由业务侧路由至当前厂站接听人，不能靠帽端传入 `targetUserId` 任意选择员工。安卓只展示分配给当前账号的来电。

现阶段联调使用在线值班映射，正式“当前排班值班人”接口尚未接入。角色人员列表不是实际当班记录。若存在多个候选且无法判定当前值班，应明确处理歧义，不能将最新心跳或列表首项伪称正式排班结果。另一任务如完善路由或管理员管理能力，需要保持上述身份与厂站边界，并明确当前测试映射规则。

## 5. Java 18084 实测结果

执行脚本：`新版安卓端开发/音视频网页联调/test/live-backend-bridge.mjs`。

脱敏结果：`新版安卓端开发/音视频网页联调/artifacts/live-backend-bridge.json`。本次状态 `passed`，15 项断言通过，30 个客户端请求的 origin 全部为 `http://127.0.0.1:18084`，没有客户端直连 Node 请求。`bridge-info` 精确返回 Java / virtual-helmet 标识。

本次通话 ID：`da7aa36d-2fdb-4381-85af-6b81241d2e81`。

首次接通时间戳：`1789882518373`。从第一台安全帽接听、管理员代控开关、值班端开关、第二台安全帽加入到结束，`callId` 和 `connectedAt` 保持不变，没有二次响铃。

实测同时确认：

- 只读账号和普通非会话账号操作画面被拒绝；跨厂站请求被拒绝 / 不可见。
- 同站管理员可以开启 / 关闭原通话画面，符合用户本轮明确要求。
- 未接通时开启、结束后再次开启均返回冲突。
- 最终会话为 `ended`，`videoEnabled=false`，现有安全帽 `12 / 13` 均已关闭模拟在线。

测试未修改真实佩戴、未生成 SOS 事件、未测试手机摄像头或真实音视频。首次按旧“管理员不得代控”断言得到失败记录，已保留在 `artifacts/live-backend-bridge-first-permission.json`；随后根据用户明确的新权限语义调整测试并重新通过，没有改业务实现来迎合断言。

原 28 项 Node 服务回归本次全部通过，结果在 `artifacts/backend-bridge-server-regression.log`。这份接口实测与 Android 真机 / 模拟器 UI 验收是不同证据，不能互相替代。
