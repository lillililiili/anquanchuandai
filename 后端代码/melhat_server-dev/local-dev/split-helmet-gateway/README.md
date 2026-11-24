# 分体式安全帽接入与联调

本功能在智能穿戴自己的设备、人员领用、事件、调度、地图和资料业务中增加 `SPLIT_HELMET / ZLM_WEBRTC` 分派。设备类型仍为 `HELMET`。厂家凭据仅留在后端；原安全帽平台源码及其业务接口均不作为运行依赖。默认关闭，交付代码和配置样例不等于已经接入真实设备。

**同一 SN 不应同时在两套平台保持有效控制登记。** 已有设备移交时，先结束原平台通话和录像，再退出旧平台有效台账。不得只修改回调路由而保留两端控制权限。设备名单、厂家配置、正式推送地址切换及实机验收由接入负责人安排，本次不自动迁移设备或修改线上配置。

## 组件与数据

| 组件 | 职责 |
| --- | --- |
| `com.ruoyi.melhat.split` | 独立 v1.12 认证、设备查询、回调收件箱、WebRTC 会话、媒体指令和文件代理 |
| `GuardianSplitHelmetBridge` | 将已登记帽子的定位和报警送入现有历史、归属及事件闭环 |
| `gateway.mjs` | 按 SN 分流厂家唯一回调地址；SQLite 保存新端待投递消息 |
| `../wear-api-gateway/gateway.mjs` | 客户端会话、SDP、文件下载入口的精确白名单 |
| PC / Flutter | 单独的 ZLM 双 PeerConnection 适配；沿用本系统会话和领用版本 |

数据库增量为 `../../ruoyi-admin/src/main/resources/db/20261116_split_helmet.sql`，含 `split_helmet_inbox/state/session/lease/command/event/file`。部署时对目标智能穿戴数据库执行一次并核对权限；脚本可重复执行。启用适配器时也会用同一脚本检查建表。原业务主数据仍是既有 `wearable_*` SQL 台账，不新增业务 JSON 主账。

分体帽控制适配器按 **单活后端** 部署，禁止两台 Java 实例同时启用本配置和清理任务；回调网关同样使用单实例。厂家挂断以 SN 为单位，没有跨实例会话隔离标识。SQL 占用用于进程恢复及本系统会话校验，不能据此宣称厂家控制支持多活。切换后端实例前先停止旧实例，保留 SQL 会话和占用记录，由接替实例恢复清理。

`split_helmet_inbox` 保存原报文、归属快照、设备时间、网关接收时间、投递 ID 与处理状态；`split_helmet_state` 是按字段时间更新的最新遥测；定位完整历史和报警闭环复用 `helmet_location_fix`、`helmet_event_link`。不要删除待处理收件箱、未结束会话或设备占用行来“解锁”。

已鉴权、已登记报文中的非法测量会保留在收件箱并标为拒绝处理，防止堵住该 SN 的后续数据；不会把非法值写成零。`projected` 为 0 表示待处理、1 表示已处理、2 表示拒绝处理，拒绝原因保留在报文的 `validationError`。未知 SN 和认证失败仍拒收。文件使用独立 `split_helmet_file` 索引，不因最近指令列表截断而丢失历史访问依据。

## 准备后端和手动建档

1. 使用独立测试数据库先验证增量脚本、后端及三端构建。当前项目日常 PC 开发入口可能连接正式云端，联调前明确指定隔离地址。
2. 复制 `application-split.example.yml` 到部署私密配置目录，以附加 Spring 配置加载。设置独立 `SPLIT_HELMET_CLIENT_ID`、`SPLIT_HELMET_CLIENT_SECRET`、不少于 32 字符的 `SPLIT_HELMET_CALLBACK_SECRET`。不要沿用或覆盖一体帽的 SIP、媒体及厂家凭据。
3. 管理后台选择“安全帽 → 分体式安全帽”，分别填写平台编号 `code`、资产序列号 `sn`、厂家 `helmetSn`（内部字段 `deviceNumber`）。创建后接入身份固定；名称、业务资料仍按原规则维护。禁止使用另一来源已占用的身份。
4. 在 `SPLIT_HELMET_ALLOWED_DEVICES` 填写本次明确交给智能穿戴的厂家 SN。必须同时满足手动台账、启用厂站、有效设备及白名单；不会导入厂家账号下的其他帽子。
5. 核对 `SPLIT_HELMET_FILE_ORIGINS` 中每个录像机源站。文件通过本系统鉴权代理访问，浏览器和安卓不会拿到厂家 Token 或未校验的远程文件 URL。厂家返回地址还须匹配设备路径；历史时间/归属不能核实的文件不会开放下载。
6. 完成下面回调网关配置后，将 `melhat.split.enabled` 改为 `true` 并按常规部署流程启动。未启用时不对厂家发起调用，三端显示未配置/状态未知。

厂家 API、SDP 和媒体网络需分别验证。API 为 HTTPS；ZLM 媒体 ICE 依厂家文档使用 UDP/TCP 8000，客户网络需可达。信令只经本系统按会话和设备授权的入口转发。厂家设备注册、MQTT 和中继继续由厂家中间件维护，本项目不重建这些服务。

厂家文档示例中的录像机可能只提供内网 HTTP；只有显式列入 `file-origins` 的精确源站才允许这种服务端读取，不能配置任意 URL 或宽泛域名通配符。客户端仍只访问本系统 HTTPS 文件代理，厂家 Bearer 不转发给录像机，重定向不自动跟随。

## 唯一回调地址的 SN 分流

需要 Node.js 22.19 或更新的兼容版本，使用内置 `node:sqlite`，没有 npm 运行依赖。生产只有一个网关进程操作一个持久化数据库；不要用多个 worker 同时消费同一 SQLite 文件。监听仅回环地址，外部 HTTPS 由现有反向代理提供。

复制 `config.example.json` 并填入真实目标地址。其中 `legacyOrigin` 是原平台的回调基址，程序会追加 `/api/helmet/notify/{kind}`；应核对原平台是否需要 `/prod-api` 前缀。`wearableOrigin` 对应本系统专用回调路径，例如 `https://wearable.example/split-callback`。任何目标都不能指回本分流入口，避免循环。示例没有真实设备登记。

显式登记示意（仅说明格式）：

```json
"routes": {
  "YOUR_REGISTERED_HELMET_SN": "wearable",
  "YOUR_PAUSED_HELMET_SN": "paused"
}
```

SN 区分大小写、精确匹配；未列出的 SN 同步转发旧平台并返回旧平台状态和响应体。`paused` 返回 409，已有新端队列也暂停投递，始终不会自动退回旧平台。每次变更增加 `version`，保留原配置版本，重启加载。要暂停设备，应保留其 `paused` 条目，不能删除条目；删除意味着后续新报文匹配默认旧端。

为进程配置：

```text
SPLIT_ROUTER_CONFIG=/etc/wearables/split-router.json
SPLIT_ROUTER_INCOMING_SECRET=<厂家现有回调密钥，保持与旧平台一致>
SPLIT_ROUTER_WEARABLE_SECRET=<与后端SPLIT_HELMET_CALLBACK_SECRET一致的独立密钥>
```

`databasePath` 必须为可写、持久化的绝对路径；父目录由部署人员创建并限制访问。可参考 `split-helmet-router.service.example`，确认 Node 实际路径、用户及读写目录后使用。`Caddyfile.example` 仅示意精确六类回调的代理，不能覆盖现有站点配置。程序启动方式：`node gateway.mjs`。完成隔离回放、原平台透传和恢复验证之后，接入负责人再切换厂家 `notify_host`。

新端报文先持久化再确认接收，后台按每个 SN 的顺序投递，携带固定 `X-Split-Ingress-Id` 和 `X-Split-Received-At`。下游必须同时返回 HTTP 2xx 和 JSON `code:200` 才视为确认；失败指数退避，最长间隔 300 秒。重启继续使用原 ID、接收时间、目标和路由版本，路由变更不会把历史消息改投另一平台。对厂家重新发送、却没有唯一事件 ID 的报警，网关会保留每次接收证据，由后端现有告警聚合规则合并。

旧端不会进入自动补发队列。旧端超时返回 502 表示投递结果未知，不代表原平台没有处理；网关不会据此重发旧端告警。SQLite 无法打开或写入时，新端拒收 503，旧端同步透传继续工作。检查磁盘空间、目录权限和存储健康，恢复后用原数据库重启；不要用空数据库替换未确认队列。

可用 SQLite 工具只读检查：

```sql
SELECT acknowledged, COUNT(*) FROM delivery GROUP BY acknowledged;
SELECT seq,sn,kind,attempts,last_status,received_at,route_version
FROM delivery WHERE acknowledged=0 ORDER BY seq LIMIT 100;
```

保护数据库及 WAL 中的原始定位/报警数据。备份使用 SQLite 一致性备份，或停止该网关后完整复制数据库和对应 WAL；不要只在运行中复制主文件。保留证据周期由既有运维要求确定，本实现不自动清除未投递记录。

## 三端行为和权限

### 在实时监看中对讲

PC 前台打开「调度通信」，在「人员」中选中一名已领用分体帽的人员，点击「查看实时视频」。画面就绪后点击「开启对讲」，允许使用麦克风即可边看边说。点击「关闭麦克风」会继续播放视频。多选分体帽佩戴人或选择本系统的分组时，可使用「多帽视频对讲」，上限为 8 顶。

安卓从「现场 → 全厂设备 → 分体帽详情 → 实时观看」进入。画面就绪后可以开启对讲，关闭麦克风后仍可继续观看。两个客户端都在首次开启对讲时申请麦克风，并使用观看会话原有的设备占用和心跳。后端按当前领用及版本复核观看、语音和视频通话权限。仅有观看权限时仍可看画面。

如通过云服务器的私有 PC 入口联调，还需核对该入口的设备控制权限。当前部署的 `PC_ALLOW_BUSINESS_WRITES=false` 会拦截开始观看和对讲的控制请求。当前电脑的 PC 入口和安卓使用原云 API。

### 接口和会话

- `GET /devices/{sn}/live`、设备媒体和指令、通话/广播 API 延续既有路径，以来源分派。新增 `/api/guardian/v1/split/sessions/{id}/heartbeat`、`/end`、`/devices/{sn}/play|talk` 和 `/split/devices/{sn}/files/{id}`。云网关已增加精确方法/路径白名单，SDP 使用 `application/sdp`，文件支持单范围 `Range`。
- 单呼、群呼和本系统分组通话最多 8 顶分体帽。调度员一次申请麦克风，把同一音轨发送到各帽，分别接收各帽音视频；帽子之间不互听。SIP 一体帽与分体帽应分开呼叫。
- 直播和对讲共用设备级占用。创建先保存意图和占用；每 60 秒续期；退出、失联、撤权、归还及重启恢复按已保存会话清理。结束请求必须属于该内部会话，迟到请求不会挂断后来创建的会话。挂断结果未知时保留占用继续核实，不允许直接重拨。
- 人员操作携带 `personId/assignmentId/assignmentVersion`，后端重新校验当前领用、厂站及功能权限。旧页面在归还、换人、停用或撤权后不能续期或新发指令；清理请求仍绑定原会话/原录像 SID。
- TTS 单播、群播、组播只报告厂家受理，不报告现场播放成功。抓拍保存厂家任务标识；录像保存 SID，默认 300 秒，范围 1～86400 秒。创建类超时保留结果未知，不自动重发。实际录像状态和文件生成分别展示。
- 文件包含图片、视频、音频；下载仍检查当前账号的厂站/区域权限，但文件归属取文件时间对应的历史领用快照。目录 `lastModified` 只代表文件修改时间，不证明操作摄像头的人。缺少可信时间或历史记录时不把文件归给当前佩戴者。
- 在线由设备查询确认。接口失败显示未知，不把缺字段变成 0。电量、位置、气压、温度和各 TF 字段独立保留时间和新鲜度；旧报告不覆盖新值。位置按文档 WGS84；TF 保留原始容量字符串及状态，不猜容量单位。
- `sosCall`、`sos` 中的 SOS/脱帽/跌落进入统一事件；保留跌落时间和加速度原始字段。`sosCallEnd` 只补充结束呼叫证据，不能替代人工核验告警。脱帽消息不能推断后续已重新戴帽。

## 隔离自动化与实机验收清单

自动化命令在各项目目录运行：网关 `node --test test/*.test.mjs`；PC `npm test` 与 `npm run build`；后端 Maven `-pl ruoyi-admin -am test`；Flutter `flutter analyze`、`flutter test` 和 Android 构建。后端新增 `SplitHelmet*Test`、`GuardianSplitHelmetBridgeTest` 与 `SplitHelmetRegistrationTest`，覆盖接口桩和 SQL 持久化。准确执行结果见同目录 `VALIDATION.md`。

隔离环境应逐项验收：

1. 两类帽和安全带并存，原 SIP、媒体和权限不退化；手动建档、重复厂家编号、重复资产身份、未知 SN、跨厂站、归还重领。
2. 六类回调鉴权、缺字段、零电量、异常时间、重复和乱序；重启仍能处理收件箱；SOS 结束不关闭事件，核验后原始证据仍在。
3. 分流准确，旧端故障不自动补发，新端故障持久化重试；暂停 SN 的新旧队列均不改投；恢复不更换投递 ID。
4. 1 帽与 8 帽、部分返回、麦克风拒绝、ICE/信令失败、网络中断、退出/重启、迟到挂断；检查占用释放只发生在确认清理之后。
5. TTS、带水印抓拍、1/300/86400 秒录像与非法时长、SID 停止/状态；超时不重发；文件任务关联、图片预览、音视频播放及下载。
6. 下载历史文件时切换账号/厂站、人员归还重领、撤权；旧页面不能继续操作，未归属文件不泄露下载地址。

真实声音、视频、GNSS 坐标、TF 数值含义和设备 SOS/脱帽/跌落按键/传感效果是后续实机验收项，接口桩通过不能替代这些结果。
