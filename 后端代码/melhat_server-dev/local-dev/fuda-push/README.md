# 福大数据主动推送（待双方联调确认）

适用于安全帽、安全带。新增推送发送端，原有 V2 位置、状态、报警查询接口继续保留，视频仍按既有国标方案单独联调。本模块默认关闭；本目录不包含真实接收地址或凭据。

## 方向与成功条件

设备上报 → 我方业务事务保存数据及待发送任务 → 提交后后台发送 → 福大保存并确认。

接收方提供一个 HTTPS POST 地址，或按 POSITION、STATUS、ALARM 提供三个地址。正文 UTF-8 JSON。

当前暂定成功响应：**HTTP 200 且 JSON 对象的 `code` 是整数 `0`**，例如 `{"code":0}`。空响应、字符串 `"0"`、HTTP 202/204、业务失败码均不算成功。福大须在成功保存后响应；已保存的重复事件同样返回成功。

## 推送信封

```json
{
  "schemaVersion": "1.0",
  "eventId": "FP-64位十六进制摘要",
  "eventType": "STATUS",
  "trigger": "REPORT",
  "occurredAt": "2026-11-02T12:00:00.000Z",
  "createdAt": "2026-11-02T12:00:00.020Z",
  "data": {}
}
```

| 字段 | 含义 |
| --- | --- |
| schemaVersion | 本推送信封版本 1.0，不替换原 V2 查询接口 |
| eventId | 我方生成的唯一推送事件 ID，重试与重启补发均保持不变；接收方以此去重 |
| eventType | POSITION 位置、STATUS 状态、ALARM 报警 |
| trigger | REPORT 设备有效业务上报、ONLINE 上线变化、OFFLINE 离线变化、ALARM 新增报警 |
| occurredAt | 此事件的观测/发生时间；报警确无时间证据时允许 null |
| createdAt | 我方生成此推送任务的时间；补发不修改 |
| data | 沿用现有查询接口 `items[]` 中单条对象的字段、类型、单位及未知值规则 |

STATUS/REPORT 是**接收当时**的状态快照，重启恢复的旧报文也保留原观测时间。它不表示推送抵达时设备仍在线。接收方更新“当前状态”应按观测时间比较，不能按 HTTP 到达时间覆盖；报警逐条入库不能因较早发生而丢弃。

POSITION.data 包含 `sourcePlatform/deviceType/deviceId/deviceModel/position/validity`。position 沿用经纬度、坐标系、positionTime/timeSource/positionMethod 等字段；无法确认坐标系时 position 可为 null。只在设备本次业务报文包含新的有效定位时产生位置事件，缓存坐标和无效 0,0 不冒充新定位。

STATUS.data 包含 `onlineStatus/lastSeenAt/offlineTimeoutSeconds/telemetryMaxAgeSeconds/battery/network/wear/hookA/hookB` 及设备标识。电量百分比 0～100；网络信号、海拔、速度等尚未确认项目继续 null/UNKNOWN，安全带佩戴和挂钩不相互代替。

ALARM.data 沿用报警查询的 `eventId/occurredAt/receivedAt/alarmType/alarmContent/rawAlarmType/rawAlarmName/alarmOrigin/positionSource/position/positionAgeSeconds` 及设备标识。外层 eventId 用于投递去重，内层 data.eventId 是稳定业务报警 ID，用于与报警查询结果对账。处置、核验、同一业务报警再次合并上报不生成新报警推送。

完整业务字段参考 [现有 OpenAPI](../fuda-api-contract/openapi.json)。推送未知值不因接收端需要而自行定义厂家枚举。

可交给对方开发者的文件：[推送 OpenAPI](openapi.json)、[位置示例](examples/position.json)、[状态示例](examples/status.json)、[报警示例](examples/alarm.json) 和 [公开签名测试向量](examples/signature-vector.json)。这些全部是虚构测试数据；测试向量中的公开密钥不得用于部署。`python build_contract.py` 可从现有查询字段定义重建资料。

## 签名与凭据

2026-11-02，用户已确认本项目主动推送复用原三个查询接口文档《01-接口账号.docx》中的 AppId 和 Secret，无需福大另行申请。推送仍使用单独的 `fuda.push` 配置项；复用凭据不会自动启用推送，也不会自动继承查询接口的设备授权。

已在本机 Git 忽略目录准备 `local-dev/fuda-cloud/.private/production/fuda-push.yml`，仅用于后续配置：`enabled: false`，接收地址及推送设备白名单尚未填写。该文件未被现有运行配置加载。福大接收端须配置相同 AppId 和 Secret 并按以下规则验签；以后轮换这组凭据时，查询与推送两端须同步更新。真实凭据不写入本说明、示例或 Git 提交。

请求头：

| 请求头 | 规则 |
| --- | --- |
| X-App-Id | 本项目经用户确认，使用原查询接口的 AppId；仍须在推送配置中显式填写 |
| X-Timestamp | 本次 HTTP 请求的 Unix 秒时间戳 |
| X-Nonce | 每次请求新生成 UUID；重试也更新 |
| X-Signature | HMAC-SHA256 十六进制小写结果 |
| Content-Type | application/json; charset=utf-8 |

签名原文以下六行以 LF 连接，无末尾换行：

```text
POST
<请求实际 URI 路径，含百分号编码，不含域名>
<X-App-Id>
<X-Timestamp>
<X-Nonce>
<HTTP 正文原始 UTF-8 字节的 SHA256 小写十六进制>
```

密钥为 Base64 编码的 32 字节随机值，使用解码后的字节计算 HMAC。不要重排或重新序列化正文后再校验。建议接收端接受 ±300 秒误差，验证签名后按 nonce 防重放。事件去重与 nonce 防重放不同：重试是新 nonce、原 eventId 和原正文。

## 可靠性与范围

- 与业务入库同事务保存 outbox，事务回滚不发送。HTTP 网络在独立工作线程执行；福大慢响应或离线不会等待在设备业务事务中。
- 单个接收目标，每个设备按入队顺序发送；某设备失败不阻止其他设备发送。默认每批最多 50 条、最小发送间隔 100ms，降低限制须结合对方容量。
- 连接默认 2 秒、整次调用默认 5 秒；不跟随重定向，不自动接受新的目标地址。
- 失败按 1、2、4、8 秒等退避，最高 300 秒；429/503 的 Retry-After 有上限。持续失败保留任务并继续重试，不静默丢弃。配置/签名错误需要运维处理，不代表最终成功。
- 租约默认 30 秒；崩溃后租约到期重新发送。福大保存后响应丢失可能产生重复 HTTP 请求，依靠 eventId 达到幂等保存。
- 推送仅包含单独白名单中的真实设备；发送前再次核对授权。撤销设备授权后的待发任务标记 CANCELLED，不再发送；重新授权不会自动复活已取消记录。
- 默认不自动补推历史报警，继续使用已有报警游标查询完成首次历史同步及补漏。设备接收队列中尚未完成业务投影的旧报文，在恢复成功后可按原时间产生事件。
- 无自动清理队列。保留送达、失败及取消记录；部署时监控队列积压、最老待发时间、磁盘容量。

## 部署与回滚

1. 使用独立分支构建并通过测试；先在隔离数据库运行。不要直接替换当前日常服务。
2. 新增 SQL 为 `ruoyi-admin/src/main/resources/db/20261102_fuda_push_outbox.sql`（随应用启动幂等初始化）。仅新增表和索引，没有删除/修改原业务表；发布前备份数据库。
3. 复制 [配置示例](../fuda-push.example.yml) 为部署环境私密配置。先保持 enabled=false；配置目标专用 destinationId、接收地址、双方约定凭据和真实设备台账 ID。本项目正式对接复用原查询 AppId/Secret，已准备的本机私密文件见上文；加载配置和启用推送仍须后续安排。
4. 获取福大测试地址，确认成功响应/签名/白名单/限流/历史范围后，在隔离环境启用。测试及正式应使用不同 destinationId 和凭据；**更换接收组织或环境时必须更换 destinationId，不能把旧任务发送给新接收方。** 同一方凭据轮换可保留 destinationId。
5. 对账“设备上报—业务入库—推送—福大去重保存”及上下线、重启、断网恢复；这些实机/外部步骤不由本地测试代替。
6. 暂停发送将 enabled=false 并按现有发布流程重启候选服务；该期间不新增推送任务，原待发任务保留。再次启用补发既有任务；停用期间报警可用查询补漏。不要将关闭推送描述成暂停采集但持续排队。
7. 回退旧应用版本保留新 outbox 表及数据，禁止删除表/清空队列。旧版本不会生成推送任务；再次升级后恢复原 destinationId 及配置，避免误投到其他环境。

可使用 [只读巡检 SQL](inspect.sql) 核对投递状态，不输出密钥和原始设备报文。

## 本地模拟接收端

可视化数据接收、国标视频点播/接收及回放，使用已集成的 [福大接口模拟器](../fuda-simulator/README.md)。以下命令仍可单独运行轻量数据接收器。

仅用虚构数据，设置环境变量 `MOCK_APP_ID`、`MOCK_SECRET_BASE64`（32 字节测试密钥的 Base64），然后执行 `node mock-receiver.mjs`；默认仅监听 `127.0.0.1:19091/receive`。`MOCK_PORT` 可换端口，`MOCK_DROP_FIRST_RESPONSE=true` 模拟已保存但首次响应丢失，`MOCK_DELAY_MS` 模拟慢响应。我方测试配置须显式设 `allow-loopback-http: true`。

示例接收端校验签名、时间戳、nonce，并按 eventId 去重；数据只保留内存，重启清空，**不可作正式福大接收服务**。正式接收端须用持久数据库唯一约束去重。自动检查：`node --test mock-receiver.test.mjs`。

## 待福大确认

测试/正式接收地址、接收端按上述规则验签并配置约定凭据、成功响应、出口白名单或专网要求、可接受频率，以及是否需要历史报警补推。AppId/Secret 已确定复用原查询凭据，不再要求重新申请；隔离测试仍使用合成测试凭据。视频参数依然按已有国标文档单独确认。
