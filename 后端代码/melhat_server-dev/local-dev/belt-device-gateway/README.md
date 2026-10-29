# 安全带专用设备网关

此网关只接收已登记的单台安全带，监听 `127.0.0.1:18087`，上游固定为 `http://127.0.0.1:18084`。它与 `../device-gateway` 的安全帽入口相互独立，不会启动公网隧道。

SOS 排查更新（2026-10-26 07:35:46–07:38:46 UTC）：用户实际按键期间，USB 原始诊断包已确认设备在成功登录的同一 TCP 连接上向正确云端地址发送 `ca_sip_sos`、`type="0"`，为完整的 116 字节 masked WebSocket 帧。1.672 秒后原样重传；本段未捕获覆盖该报文的 TCP ACK，也未捕获服务端 WebSocket Close、FIN 或 RST。同期本机网关收到 9 次遥测并获 Java 成功响应，但没有收到 SOS、未知动作或拒绝记录。SSH 隧道保持同一稳定连接，后端未重启。故已确认设备生成并尝试发送 SOS，尚需云端入口同步抓包区分具体丢失位置，不能归因为后台收到后漏存，亦不能仅凭设备 `-211` 判断服务端主动关闭。见[设备 TCP 证据](../../../../output/device-ready/belt-sos-20261026/usb-sos-tcp-conclusion.json)及[同步网关记录](../../../../output/device-ready/belt-sos-20261026/trace-usb-capture-window.ndjson)。

该次登录日志另有 `sip_cfg_ok:0`、缺少 `sip_id`/`sip_host`，但上述真实发包证明这并未阻止本次 SOS 指令发送。当前后端仍未接入 SIP 语音服务；不能将本地呼叫提示音、普通 `ca_sos` 告警或网关在线等同于紧急通话已建立。本轮未注入模拟实物报文、未修改业务处理代码。

当前状态（2026-10-26 02:45 UTC）：真实安全带已通过 4G 完成配置获取、WebSocket 握手、业务登录和遥测上报，管理端、PC 前台、安卓端对应的三个后端接口均返回 `online=true`、遥测 `CURRENT`，电量为 100。[首次核对](../../../../output/device-ready/belt-deploy-20261020/three-client-state-20261026-024315Z.json)与[再次核对](../../../../output/device-ready/belt-deploy-20261020/three-client-state-20261026-024504Z.json)之间，遥测时间从 `02:43:08` 推进到 `02:44:48 UTC`，挂钩 B 状态由 1 变为 0，三接口一致，已复核持续真实遥测。本次结论限定为真实登录与遥测三接口一致，不表示 SOS、定位质量、全部佩戴/挂钩动作语义、所有业务功能或长期稳定性均已验收。

本轮早期排查（2026-10-26 UTC）：厂家先将启动配置正文从 2999 字节精简至 916 字节；实物收到约 1405 字节完整 HTTP 回包后，日志出现 `g_config_parse_ok:1`，随后 TCP 连接成功。继续抓包发现另一个固件兼容问题：按实际字段构造的完整 WebSocket 握手应为 205 字节，设备仅发送 199 字节，结尾停在 `Upgrade: websock`，缺少完整请求头终止符，当时接收端未进入 WebSocket 升级。

随后新增由原 `pathToken` 前 24 字符派生的精确短路径 `/<shortPathToken>/wsHat`，相同字段的完整握手缩为 186 字节。原 43 字符路径继续支持，身份校验、速率与连接数限制共用原实现；不放行裸 `/wsHat`。49 项网关测试和 75 项云端隔离测试通过，本机网关已更新为当次 PID `40908`，云端 `short-ws-01` 已返回 `PREVIEW OK` / `APPLY OK`。厂家配置修改前后核对仅 `notice.ws_url`、`bootstrapConfig.ws_url` 变化。

本次成功实物启动记录 `20261026-024036Z-ttyUSB4-boot.bin` 共 11784880 字节：实际配置正文 897 字节、完整回包 1386 字节，53 字符的 `ws_url` 与短路径一致；设备完整发送 186 字节 GET 握手并收到 HTTP 101。业务日志序号 80290 为 `login server success!!!`、80303 为 `login ok start heart`；本机网关在 `02:41:20 UTC` 接受真实首帧、`02:41:21 UTC` 完成登录转发，随后由上述三接口确认真实遥测。该证据来自实物，未注入模拟登录或心跳。

本地联调记录（2026-10-21）：实物型号华能睿维 HNRW-AQD1，已登记为 `device-13`，当时处于库存、未领用状态，硬件序列号及完整设备号保留在私有资料中。网关已经启动并通过真实设备 ID 的只读配置验证和错误 ID 拒绝验证；未注入模拟实物登录，尚不能据此认定实物在线。云端 `review-02`、配置路径别名 `route-alias-01`、缺少 SNI 的兼容补丁 `default-sni-01` 及明文 WS 入口 `legacy-ws-01` 均已应用，专用 SSH 转发已连接，公网配置和错误设备拒绝验证通过；`09:59:32 UTC` 对照确认带 SNI、无 SNI 的 TLS 1.2 均通过 CA 与域名校验。网关于 `11:02:39 UTC` 重启，44 项网关测试与本地/公网错误 ID 验收通过；Java 21 项定向测试修复已上线。厂家 HTTP/WS 两项地址于 `11:09:05.852934 UTC` 回读一致，`11:11:25 UTC` 的真实设备状态仍为 `NOT_CONNECTED`，定位和状态上报仍待验收。部署记录见 [cloud/README.md](cloud/README.md)。

历史实物验证（2026-10-22 UTC）：用户已明确确认安全带已开机；`00:42:39`、`00:43:47`、`00:44:27` 三次检查仍为 `NOT_CONNECTED`，`lastSeen` 和 `telemetryReportedAt` 均为 `null`，未出现真实设备的首帧通过校验或 `ws_login_forwarded`。`00:43:25–00:43:26` 新增网关事件全部来自错误设备 ID 自检，不是实物登录。`00:43:26` 公网网关验收通过，厂家 `caps` 与文档所列 `mg` 引导接口均读回当前 HTTP/WS 地址，但尚不清楚硬件是否实际获取了这些配置。本轮云端浏览器超时，没有有效入站捕获，不能据此判断设备请求是否到达云端。当时结论为已开机但未接通；下一步需要设备端取配置结果、实际连接目标和失败日志。 证据见[最终实物状态](../../../../output/device-ready/belt-deploy-20261020/physical-after-confirmed-poweron-20261022-20261022-004427Z.json)、[本轮公网验收](../../../../output/device-ready/belt-deploy-20261020/after-confirmed-poweron-0046-public-gateway-evidence.json)、[厂家配置回读](../../../../output/device-ready/belt-deploy-20261020/after-confirmed-poweron-0046-vendor-config-read-check.json)和[引导接口对照](../../../../output/device-ready/belt-deploy-20261020/after-confirmed-poweron-0046-documented-bootstrap-comparison.json)。

更新验证（2026-10-23 02:52 UTC）：完整实物启动抓包确认，设备通过 4G 向 `caps.runde.pro` 获取配置；72 字符原地址和 28 字符短地址均确实出现在设备收到的回包中。短地址回包共 3445 字节，恢复原地址后为 3489 字节，TCP 重组后两者 JSON 均完整有效。但设备业务日志均只记录接收、处理 3072 字节，随后先报 `jsmn_parse return -1`、缺少 `status`，再报 `IP Convert fail -214`。当时需厂家核查固件配置接收和解析，不能仅将错误归因于 WS 地址格式；更后续的长路径兼容性尚未验证。原地址已恢复并回读一致，三端仍未连接、无真实遥测。本机网关已兼容实际启动表单中的 `sipphone=1`，改用明确的 UTF-8 `Content-Length`；45 项隔离测试通过，运行进程已更新，公网同格式只读配置请求返回 200、230 字节正文。设备仍从厂家启动接口取配置，因此本网关修复本身不会替换厂家回包。详见[实验汇总](../../../../output/device-ready/belt-deploy-20261020/address-format-research/experiment-current.json)及[厂家排查说明](../../../../output/device-ready/安全带待厂家确认事项-20261022.txt)。

## 配置与启动

使用 Node.js 22 或更新版本，运行 `npm ci --ignore-scripts` 安装锁定依赖。由部署人员在被 Git 忽略的 `.local/config.json` 中填写以下字段：

| 字段 | 值 |
| --- | --- |
| `listenHost` | `127.0.0.1` |
| `listenPort` | `18087` |
| `upstreamOrigin` | `http://127.0.0.1:18084` |
| `publicOrigin` | 实际公网 HTTPS origin，不含路径或末尾斜杠 |
| `deviceId` | 与代码固定登记值匹配的字符串设备号；完整值保留在本机私有配置中 |
| `pathToken` | 32 字节随机凭证的规范 base64url 编码，43 字符；私下配置并妥善保存 |

`npm run check:config` 只验证配置，不启动服务；`npm start` 启动本机网关。日志不打印配置内容、凭证或设备报文。本目录不提供或自动生成私有配置。

公网代理须将请求原样转发到此回环监听，保持路径不变并支持 WebSocket。以下普通 WS 短地址已在本次厂家配置回读和成功实物启动中确认；以后修改仍须同时核对平台读回与实物实际获取：

- HTTP 请求地址：`http://caps.runde.pro/api/`
- 长连接地址：`ws://39.106.212.138:80/<shortPathToken>/wsHat`，其中 `shortPathToken = pathToken.slice(0, 24)`，不是新增配置字段。

原 `ws://39.106.212.138:80/<pathToken>/wsHat` 和 `wss://<公网域名>/<pathToken>/wsBelt` 路径继续支持。三条精确路径均转发后端 `/wsBelt`，共用身份校验与限制；短凭据保留 144 bit 随机性，完整 43 字符凭据继续保存在原配置中。裸 `/wsHat`、短凭据的 `/wsBelt` 和 HTTP 配置路径不放行，不改变安全帽端点。

HTTP 字段保留厂家业务接口目录 `api_url`，实时登录、状态及告警通过我们独立的 `ws_url` 接入。设备内置的“获取配置地址”（bootstrap）是另一项设置；修改 `api_url` 并不表示已经改变 bootstrap。本次短路径下发已由新的回读与实物日志验证，此前完整路径的历史保存记录不替代新的验证证据。

现有完整私有路径下的 HTTP 配置端点保留为 fallback：若设备仍请求它，回包中的 `api_url` 固定为 `http://caps.runde.pro/api/`，`ws_url` 返回上述普通 WS origin 加 24 字符短路径。网关只从固定本地后端读取该配置，不请求或代理厂家 HTTP 服务，不允许任意转发目标。短路径代码已于 2026-10-26 UTC 更新进程；它不自动修改厂家平台或本机 `.local/厂家平台配置.txt`。修改说明本身也不会改变运行进程。

## 接收范围

- 仅 `/<pathToken>/api/belt/index.php` 及厂家配置接口兼容路径 `/<pathToken>/api/belt/config/index.php` 的 `GET` 或 `POST` 配置请求，参数必须为 `ctl=config&act=get_config`，并携带对应 `device_id` 或 `imei`。两条路径使用相同校验；两种设备号同时存在时必须都匹配固定设备 ID。返回的 `api_url` 为固定厂家目录 `http://caps.runde.pro/api/`，发往本地后端仍统一使用 `/api/belt/index.php`。
- POST 支持 URL 查询参数及最多 2048 字节的 `application/x-www-form-urlencoded` 表单，要求明确的 `Content-Length`。拒绝重复参数、分块请求、JSON/multipart 请求体、上传和任意其他转发目标。
- `app_version`、`ic`、`ca_ver` 是可选、有长度限制的固件参数；`sipphone` 为可选的 `0`/`1` 标记，兼容实物 RD1102 启动 POST。均验证后丢弃。发往后端的参数始终只含 `ctl`、`act` 和规范化后的 `device_id`，路径固定为 `/api/belt/index.php`。JSON 响应显式给出 UTF-8 字节长度，不使用分块响应，降低嵌入式 HTTP 解析要求。
- WebSocket 仅接受 `/<pathToken>/wsBelt`、`/<pathToken>/wsHat` 与 `/<shortPathToken>/wsHat` 三条精确路径，首帧必须是 `ca_login`，并有匹配的字符串 `device_id`。后续允许 `ca_report_location`、`ca_sos`、`ca_sip_sos` 和同设备重新登录。每帧出现的 `device_id`、`imei` 均须匹配固定 ID；首帧身份校验通过后才连接后端 `/wsBelt`。
- JSON 文本帧上限 64 KiB，最多 4 条连接；有请求、升级、消息速率限制，以及认证、空闲和上游超时。二进制帧、其他路径、其他动作和身份切换均拒绝。

## 隔离测试

运行 `npm test`。测试使用随机分配的回环端口和内存中的非保密测试凭证，不读写 `.local`，不访问日常后端 `18084` 或厂家 HTTP 服务，不向真实设备登记注入模拟报文。覆盖厂家 HTTP 与自有 WS 的独立配置、WS 无需本地 HTTP fallback 即可登录上报、GET/POST 兼容、身份冲突、路径限制、超时、队列/负载/速率限制和连接清理。

配置路径别名还需云端 Caddy 同时放行。既有 `review-02` 部署使用 [独立路由补丁](cloud/README.md#已部署-review-02-增加配置路径别名)，不能重跑原部署来添加别名；仅更新本地网关不会改变云端路由。普通 WS 的 IP:80 完整私有路径经 `legacy-ws-01` 应用，24 字符短别名再经 `short-ws-01` 追加，未新增端口映射。回滚顺序为 `short-ws-01` → `legacy-ws-01` → `default-sni-01` → `route-alias-01` → `review-02`，详见[云端短路径说明](cloud/README.md#短路径-websocket-兼容补丁已部署)。

## 接入观察日志

CLI 启动的网关将观察记录写入被 Git 忽略的 `.local/belt-gateway-events.ndjson`，每行只有 UTC `time`、固定枚举 `event` / `reason` 和该组合自进程启动以来的累计 `count`。不记录路径凭据、设备 ID、查询参数、正文、坐标、网络地址或异常文本。当前文件及两个轮转文件合计最多 768 KiB，每秒最多写入 50 条；超过速率的记录被丢弃，后续同类记录的累计计数仍会推进。文件写入失败时停止本进程的日志写入，不影响设备连接。直接调用 `createBeltDeviceGateway(config)` 默认不启用观察；需要时传入第二个参数 `{ observer(record) {} }`，回调异常不会改变接入结果。

| 观察事件 | 可判断的阶段 |
| --- | --- |
| `transport_connection / open` | 本机网关收到 TCP 连接；未采集字节，可与后续 HTTP/WS 事件对照 |
| `http_request / received`，`http_result` | HTTP 已到达；结果区分路径、方法、参数、动作、缺失/不匹配身份、限流和上游失败 |
| `ws_upgrade / received`，`ws_upgrade_result` | WS 升级已到达；区分路径拒绝、容量/速率限制和握手结果 |
| `ws_first_frame` | 首帧已到达或超时；区分 JSON/结构/动作错误、非登录首帧、设备号缺失、类型错误或不匹配，以及通过校验 |
| `ws_upstream` | 开始连接、连接建立、失败或关闭 |
| `ws_login_forwarded / ok` | 已校验的登录帧完成向上游发送；不等于后端确认登录，也不代表实物验收通过 |
| `ws_action_received` | JSON 对象已到达；只记录固定指令枚举，其他动作统一记 `unknown`，不保存原始动作内容 |
| `ws_action_validated`，`ws_action_forwarded` | 指令通过既有校验、向后端发送的回调成功；排队时不提前计为已转发 |
| `ws_login_response`，`ws_location_response`，`ws_sos_response`，`ws_sip_sos_response` | 后端返回相应指令的响应，结果仅为 `true` / `false` / `invalid`；不保存响应正文 |
| `ws_error_response`，`ws_response_invalid` | 后端通用错误响应或无法识别的响应格式；观察不改变原始回包的转发 |
| `ws_frame_rejected`，`ws_session` | 后续报文拒绝、队列限制、发送失败、空闲或连接关闭 |

日志中的探针与实物使用同样的事件，需按实际操作时间区分；没有事件不能排除请求在 DNS、TLS 或云端入口之前失败。观察不会放宽数字型设备 ID、动作、路径或任何既有限制。启用新代码需要由操作者重启安全带网关；查看日志本身不重启任何进程。
