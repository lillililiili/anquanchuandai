# Android 接口联调与发布交接

本清单由 Android 侧整理，2026-09-10；基线提交 `a6ed499`。后端、数据库、PC、共享契约未修改。本地后端和示例数据的验证只能证明当前开发环境可用，不能替代线上和硬件验收。

## 已采用的接口事实

| 事项 | Android 使用方式 | 需要同步的文档差异 |
| --- | --- | --- |
| 身份与厂站 | `/login` 外层 token，`GET /api/v1/me`，`PUT /api/v1/me/current-site`；业务请求携带 `X-Site-Id` | 人员 ID 与登录账号 ID 分开，不使用姓名绑定 |
| 当前装备 | `/api/v1/people/{id}/equipment`、`/api/v1/me/equipment` | 旧交接稿 `/assignments/current` 不适用 |
| 转派 | `/api/v1/duty/operators`；提交账号 userId | 候选操作员与 `/people` 人员选择分开 |
| 事件角标 | `/api/v1/events/inbox/count` | 标为“待处理”；已读不减数量 |
| 已读权限 | 按当前服务端可见范围执行 | 已读与认领/处置/复核权限不同 |
| 事件推送 | WebSocket `/ws/{userId}/2?token=...`；HTTP 再读状态 | `{userId}_2` 是服务端内部索引，不是路由参数；提醒消息不保证每次操作都发送 |
| 同步 | 通知、回前台、重连、完成操作刷新；前台 30 秒校准 | 没有版本/通知 ID 的旧 WS 消息不永久去重；不能依赖 updatedAfter 补齐已关闭事件 |
| 作业事件 | `/api/v1/work-tasks/{id}/events` | `/events` 未提供 taskId 筛选，Android 不向其发送无效参数 |
| 待人工关联 | `POST /api/v1/events/{id}/task`，body: taskId/version | 多任务命中由有权限的人员手动确认 |
| 工作台 | `/api/v1/duty/summary` | peopleCount/deviceCount 是已领用人员和在用装备；lostSupervision 是进行中任务里安全帽检查异常的去重人数 |
| 通讯 | 服务端通话状态轮询 + 本地 RTC 状态 | 请求成功不等于接通；目前不依赖未实现的通话 WS |
| 轨迹 | 人员稳定 ID，from/to/current/size；读完返回的采样分页 | 接口最多提供的采样集合并非设备全部原始点；位置来源、时间、质量保留 |

## 新增推送接口提案：尚待后端实现

`PUT /api/v1/me/push-installations/{installationId}`

```json
{
  "provider": "jpush",
  "registrationId": "provider-issued-id",
  "platform": "android",
  "appVersion": "1.3.0+7",
  "notificationPermission": "granted"
}
```

`notificationPermission` 为 `granted` 或 `denied`。installationId 是应用安装实例的随机标识，不是硬件标识；账号从登录态确定。建议按 installationId 幂等绑定，换账号时原绑定失效。权限撤销、账号停用、令牌过期与退出后，不再向无权账号投递。`DELETE` 同一路径只解绑当前账号的该安装实例，重复删除应幂等；不能删除其他用户的绑定。

绑定/解绑需要事务内校验有效登录态并原子更新安装归属，防止慢 PUT 在退出 DELETE 或新账号绑定之后重新写回旧账号。Android 已串行执行整段原生与 HTTP 生命周期，并在服务器确认 PUT 之后才恢复接收；HTTP 取消/超时无法撤销服务端已接收的事务，最终顺序仍必须由服务端保证，必要时增加安装绑定修订号。此项未实现前不能开放生产推送。

载荷 extras 示例：

```json
{
  "type": "wear.event",
  "notificationId": "unique-delivery-id",
  "eventId": "stable-event-id",
  "siteId": "authorized-site-id",
  "eventVersion": 3
}
```

锁屏标题建议“有新的现场待处理事项”，正文不含姓名、位置、事件描述。通知点击后客户端重新校验登录/厂站权限并通过 HTTP 取详情，载荷不支持任意 URL 或执行指令。推送应由服务端按厂站及权限投递，记录通知 ID、渠道、发送时间、结果和失败原因，日志不要输出凭据或敏感正文。

Android 已创建 `wear_events` 高重要性、私密锁屏通知频道，发送配置使用该频道（例如极光 Android notification 的 channel_id）。需真机验证普通通道及各厂商通道实际采用的频道与锁屏样式。

## 需要联合验收的外部条件

**当前源码发现的发布阻断项：WebSocket 鉴权与多连接。** `SecurityPathRules.java` 将 `/ws/**` 放行；`WebSocketSever.onOpen` 直接以 URL 中 client/type 登记连接，没有校验 token 或其对应账号。Android 在 query 传 token 并不等于后端已校验。请后端在握手阶段验证登录态及账号一致性，拒绝伪造 client，停用/撤权后关闭连接；禁止日志记录完整敏感消息。此外现有 `onClose` 无条件 `sessionPool.remove(sessionKey)`，旧连接晚关闭可能移除同账号的新连接，需按 session 条件移除或支持多安装实例。Android 已保护自身重连代次并保留 HTTP 30 秒校准，但不能代替服务端修复。本轮未修改这些后端文件，也未测试截获他人消息。

1. 真机可访问的 HTTPS/WSS 地址及证书链；当前 `10.0.2.2:18084` 仅供 Android 模拟器访问开发机。
2. 极光应用与厂商辅助通道申请、签名指纹/包名一致的配置；后端安装绑定、解绑和发送记录接口。不能把“SDK 已编译”标作“锁屏可达”。
3. 真实声网 App ID、短期凭证、呼叫状态推进、真实装备端音视频响应、权限拒绝和超时联调。演示 call 不启用真实 RTC，不作为验收证据。
4. 接警真机矩阵：前台、后台、锁屏、系统回收、重复通知、断网恢复、冷启动、换账号、撤权、通知拒绝。用户强行停止/关闭通知单独记录，不承诺必达。
5. 角色矩阵：值班、班组长、复核、只读、平台账号；抢单 409、跨站、历史人员快照、PC 关闭后的 Android 校准。
6. 后台持续音视频需要根据选定设备与系统版本进一步验证原生前台服务、麦克风/摄像头后台限制。本版没有将“切后台仍持续通话”标记为生产已通过。

## 保留与延期

旧页面、工具与原服务代码保留在工程中；正式入口不再注册旧业务路由。仅 debug 包显式 `LEGACY_DEMO=true` 可用于旧版比对。安全带真实遥测、楼层定位、组呼、录制、围栏编辑、完整两票、AI、签到不纳入本版正式验收。未知楼层/电量/陈旧位置不能转成正常状态，演示数据明确标注。

参考：[极光 Flutter 插件](https://github.com/jpush/jpush-flutter-plugin/tree/dev-3.x)、[Android 厂商通道](https://docs.jiguang.cn/jpush/client/Android/android_3rd_guide)、[Android 通知权限](https://developer.android.com/develop/ui/compose/notifications/notification-permission)。
