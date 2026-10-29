# 本地设备接入模式

三端共用账号、事件、SOS 接口及第二阶段验收记录见
[三端共用后端-第二阶段实施与验收](../../../新版安卓端开发/开发任务拆分/三端共用后端-第二阶段实施与验收.md)。

## 已有数据库升级（页面缺字段报错）

Docker 的 `/docker-entrypoint-initdb.d` 脚本只在数据卷首次初始化时执行。
已有数据库不会因为重启或重新构建镜像而自动补列。
遇到 `sys_dept.dept_code` 或 `electronic_fence_alarm.fence_id` 缺失时，
使用 `sql/migrations/20260916_page_schema.sql` 做增量迁移，不要重跑包含 DROP TABLE 的完整初始化脚本。
此迁移只补充缺失的可空字段和索引，可重复执行，不删除或改写现有业务记录。
历史围栏告警的 `fence_id` 留空，不能用 `hat_id` 猜测围栏归属。

在本目录通过 PowerShell 执行：

```powershell
Get-Content -Raw ../sql/migrations/20260916_page_schema.sql | docker exec -i melhat-mysql sh -c 'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD" --default-character-set=utf8mb4 new-helmet'
```

默认 `MELHAT_DEMO_MODE=false`：走原有真实设备服务，不将调用失败转为模拟成功。
旧页面的模拟兼容接口仅在 `true` 时注册；真实模式下这些尚无真实实现的接口返回未找到，不冒充真实数据。

在本目录创建 `.env`，参考 `.env.example` 填写平台提供的账号凭据。
不要把平台凭据提交到 Git，也不要在聊天中粘贴密码。
默认平台地址使用 `https://api.hel.epplink.com:30090`，认证及设备查询通过 HTTPS 访问；基础地址末尾不加斜杠，接口路径自带斜杠。

重新构建后端 JAR 后，在本目录执行：

```powershell
docker compose up -d --build --no-deps backend
```

仅离线演示时设置 `MELHAT_DEMO_MODE=true`，重新创建 backend 容器。
该模式下对讲、广播只保存本地记录，不调用真实 RTC/TTS。

切换模式不会清空数据库。已有 MH-DEMO-* 记录仍是模拟数据，不能作为设备已在线的证据。
连接验证应先检查认证及设备列表，获得授权后再验证真实通话/广播。

## 真实设备清单同步

真实模式下，管理员登录后可使用以下接口（携带后台登录 Token）：

- `GET /hat/safety/info/platform/devices`：只读预览账号下的平台设备。
- `POST /hat/safety/info/platform/sync`：按 SN 同步设备，返回新增、更新、未变和跳过已删除记录的数量。

同步只新增缺失设备或更新已有设备的平台状态/通信标识，保留已有人员、群组及媒体配置。
新增设备的人员和群组绑定留空。已软删除的设备不自动恢复；重复编号或无效平台状态会中止同步。
没有平台匹配的旧记录仍保留，查询显示 `平台未确认`（状态 `-1`），不计入在线/离线统计。
设备列表与状态筛选使用平台查询结果；查询失败会报错，不以数据库旧状态替代。
只有只读设备查询在收到 401 时会刷新认证并重试一次，通话和广播不自动重放。

需要设备上线后才能验收：实时定位与时间戳、视频、对讲、广播、SOS/告警上报。
导入设备编号并不代表这些能力已经验证；离线设备的旧坐标也不代表当前位置。

## 一体式安全帽直连（1020 安全帽源码协议）

2026-10-20 新增的接入路径参考 `1020源码/安全帽/smart_helmet_server`。
它与上面的厂家 HTTP 云接口是两种接入方式，不需要用头箍云平台账号代替一体帽注册。
三端继续使用同一个 guardian 后端、资产台账和人员领用关系。

### 登记与网络配置

1. PC 后台新建安全帽，选择“一体式安全帽直连”，分别填写平台编号、设备登录 ID 和 S/N。
   `deviceNumber` 必须等于固件实际发送的 `device_id`；铭牌 ID、S/N 不是同一个字段，
   尚未取得实际登录报文时不能凭经验断定固件使用哪一个。身份字段建立后不随发放、归还改变。
2. 后端在 `safety_hat_info` 中建立明确的直连档案；仅此类预登记设备可以登录。
   普通资产、示例设备、厂家云设备和已停用的直连档案不能直接取得接入资格。
3. 在本目录 `.env` 中设置以下变量，再按既有方式构建、更新后端容器：

   ```dotenv
   MELHAT_DEMO_MODE=false
   MELHAT_DIRECT_ENABLED=true
   MELHAT_DIRECT_PUBLIC_BASE_URL=https://设备可访问的服务域名
   MELHAT_DIRECT_WS_URL=wss://设备可访问的服务域名/wsHat
   MELHAT_DIRECT_HEARTBEAT_TIMEOUT_SECONDS=45
   ```

   HTTP/WS 共用应用端口，当前本机服务为 18084。局域网 Wi-Fi 可用设备能访问的本机地址；
   4G 卡不能访问电脑的 `127.0.0.1` 或普通局域网地址，需要设备能访问的公网服务地址。
   反向代理需转发 WebSocket Upgrade，并允许超过心跳周期的长连接。
   当前联调采用 USB reverse；尚未建立公网入口。

4. 设备端的引导配置地址设为：
   `http://<设备可访问的主机>:18084/api/index.php?ctl=config&act=get_config`。
   固件在请求时自行追加 `device_id`、版本等参数。保留原源码入口
   `/api/melhat/config/index.php?ctl=config&act=get_config`，兼容已有设备配置。
   `data.config` 是 JSON 字符串，其中 `api_url` 默认是 `http://<主机>:18084/api/`，
   `ws_url` 是 `ws://<主机>:18084/wsHat`。协议文档规定固件在 `api_url` 后拼接
   `index.php?...` 或 `upload?...`，所以这里是带尾斜杠的目录，不能重复拼接 `index.php`。
   若需要独立 HTTP 目录，可设置 `MELHAT_DIRECT_API_URL`（Spring 属性
   `melhat.direct.api-url`）；最终以该固件实际发出的请求为准。
5. 通讯会话以 `ca_login.device_id` 绑定设备。后续报文不能冒用其他设备编号，
   人员归属从服务端领用关系确定，客户端上送的 `user_id` 不参与授权。

协议仅凭预登记的设备 ID 识别设备，参考协议没有密码或签名字段。
这不是强设备认证；正式公网使用前需要厂家确认支持的设备认证方式，并限制设备入口的网络访问。
SIP 密码、数据库密码和厂家凭据不应写入源码、资产表单或公开配置响应。

### 交付资料中已确认的配置入口和 USB 工具

2026-10-20 对照了 `1020源码/安全帽` 和同目录的
`一体式安全帽-对接设备端接口文档250916.pdf`，发现两层不同的配置：

- 设备内置的“获取配置地址”决定首次请求发到哪里。PDF 第 2 页说明：可以保留厂家
  CAPS 引导服务，在该平台“开关设置”修改 HTTP 请求地址和长连接地址；带摄像头的型号
  也支持修改帽子内置的引导地址。但交付 PDF 只写了“修改方法一、修改方法二”，
  没有附具体设备菜单、按键或二维码格式，不能据此编造操作步骤。
- 原源码收到获取配置请求后，读取 `sys_dict_data` 的 `melhat_config_set` 字典，
  将数据标签作为参数名、数据键值作为参数值。原 PC 路径是“系统管理 → 字典管理 →
  melhat_config_set → 字典数据”，需要设置 `api_url` 和 `ws_url`。
  这组字典是全局配置，会影响所有向该服务器取配置的帽子；不会自动把尚未连接的帽子迁移过来。
  原 `MelhatController.java` 中从“参数设置”读取 `melhat_api_url/melhat_ws_url` 的代码已经注释，
  修改那两个旧键不会改变有效响应。当前项目的直连接入使用上文环境变量，不读取原系统字典。
- `安全帽安全带设备对接/日志抓取.txt` 明确要求用数据线连接电脑，并通过 QtScrcpy 目录的
  ADB 查看 `haimian` 日志；同目录附有 `QtScrcpy-win-x64-v1.4.5/QtScrcpy.exe`。
  说明里的 `http://192.168.1.109:12001/api/melhat/config/index.php?ctl=config&act=get_config`
  是交付时留下的配置地址，不能当作当前可用的本机地址。
- 三端管理 App 的后端地址、AI 服务地址和 PC 的 `VITE_APP_SOCKET_URL` 都只影响各自客户端，
  不会写入安全帽的引导地址。提供的 Android 源码是管理 App，没有发现帽内固件的服务器设置页面。

USB 实机检查先运行现有 Android SDK 的 `adb devices -l`。只有确认了非 `emulator-*` 的目标设备，
才以 `adb -s <实机序列号>` 读取属性、配置界面或短时日志；不要使用无目标的命令操作多台设备。
如果显示 `unauthorized`，需要在目标设备上完成 USB 调试授权；如果完全不出现，先确认开机、
数据线和 USB 接口。QtScrcpy 是投屏工具，尚未发现它自身包含服务器地址设置功能。
日志可能带 Wi-Fi/SIP 等凭据，不能直接整份粘贴到聊天或提交到仓库。

本机 2026-10-20 检查时 WLAN 地址为 `192.168.3.57`，后端端口为 `18084`。
该地址只适合同一局域网且设备可达时使用，DHCP 地址可能变化。

### RD-D1+ 实机确认的服务器地址文件

实机 USB 型号为 `rd_aqm6811`，帽内程序为 `com.tencent.liteav.demo`，版本 `M6811_58`。
实际 `GetConfigApi` 日志已确认 `device_id=866652021714127`，与铭牌 ID 一致；
S/N `JP2023123000336` 仍独立保存。此结论来自该台设备，不推广为所有批次的编号规则。

帽内程序 `CapUtils.getDeviceMainUrl()` 优先读取应用外置文件目录下的 `url.txt`；
`setMainUrl()` 写入同一文件，属于该版本正式支持的配置方式。实机路径已成功读取：

```text
/sdcard/Android/data/com.tencent.liteav.demo/files/url.txt
```

文件是一个完整的配置 URL（UTF-8 纯文本），包含 `?ctl=config&act=get_config`。
程序自动追加设备号及版本。实机原值为
`http://182.37.81.234:22001/api/melhat/config/index.php?ctl=config&act=get_config`，
已在忽略目录 `build/helmet-usb/url-before.txt` 备份。不要覆盖为铭牌 S/N 或只填服务器 IP。

无可用移动数据/Wi-Fi 时，可先建立仅该台设备的 USB 联调通道：

```powershell
adb -s 0123456789ABCDEF reverse tcp:18084 tcp:18084
```

此时设备引导 URL 使用
`http://127.0.0.1:18084/api/melhat/config/index.php?ctl=config&act=get_config`，
后端 `MELHAT_DIRECT_PUBLIC_BASE_URL=http://127.0.0.1:18084`、
`MELHAT_DIRECT_WS_URL=ws://127.0.0.1:18084/wsHat`。
这些回环地址依赖 USB reverse，只用于当前有线联调；拔线或重启后需要重新建立通道。
改用 Wi-Fi/4G 时，需要同时改引导 URL 和后端返回的 HTTP/WS 地址，不能继续使用回环地址。
写入前备份原文件并确认目标序列号，不刷机、不清除应用数据。
该固件获取配置失败后每 30 秒重新读取一次文件并重试，通常无需重启设备或应用。

当前已在默认 `site-1` 创建未领用档案 `device-12`（`RD-D1+ 实机联调`），未绑定任何人员。
后端已开启直连接入，配置 HTTP 入口已验证可用。实机重新开机后已备份并写入上述 USB 地址，
日志确认获取配置成功、WebSocket 连接成功、`ca_login.status=true`，随后连续约每 10 秒
发送 `ca_report_location` 并收到成功响应；没有发送模拟设备数据。
首次实测电量 `51`、`is_weared=1`（未佩戴）、`gps_level=-1`、空经纬度。
随后只读核对后台查询、PC 共享快照、安卓设备接口，三者均为 `online=true`、
`freshness=CURRENT`，同一时间戳上报电量 `52`、`isWeared=2/worn=true`；这是设备报告值，
用户未进行受控的戴帽/摘帽测试。因此当前验收为真实登录及基础数据同步，
未验收受控佩戴变化、有效定位、SOS 或媒体功能。
脱敏证据位于 `build/helmet-usb/real-telemetry-redacted.json`；当前连接依赖 USB，未完成 4G 公网接入。
三端核对证据为项目根目录 `output/device-ready/live-helmet-evidence-20261020-220356.json`。
管理员可见该未领用设备；普通用户只有本人有效领用后才能看到自己的设备，未自动创建领用关系。
本次备份及回滚工具在忽略目录 `output/device-ready/helmet-backup-20261020-214310`
和 `output/device-ready/helmet-maintenance.py`（相对于项目根目录），包含敏感运行配置，不提交 Git。

### 本次实现范围

| 上报 | 当前处理 |
| --- | --- |
| `ca_login` | 校验预登记身份、建立会话、记录真实连接 |
| `ca_report_location` | 更新心跳、电量、佩戴、网络、使用状态；有有效 GPS 时保存真实坐标 |
| `ca_sos` | 保存设备告警并进入三端事件；未知 `type` 保留原码，不猜跌落/近电含义 |
| `ca_sip_sos` | 保存真实设备 SOS，进入现有协助与核验流程；不报告语音已接通 |
| 断线或心跳超时 | 真实在线状态结束；旧连接关闭不会踢掉同设备的新连接 |

`x_point` 是纬度、`y_point` 是经度；`is_weared=1` 为未佩戴、`2` 为已佩戴。
`0,0` 不作为有效定位。无 GPS 仍可上报电量和佩戴，GPS 更新时间与心跳时间分开。
未绑定人员的帽子仍保存设备轨迹；坐标超出当前厂区示意图时，不挪到图内冒充当前位置。
重连或后端重启后，旧电量和佩戴值不作为新连接的实测值。

当前一体帽通信协议标记为 SIP，语音/文字 TTS 能力默认未开放。
现有 Agora 通话不能直接用于该设备；完整对讲仍需 FreeSWITCH/SIP 服务配置及对应客户端接入。
参考音频广播是音频 URL 指令，不能等同于已经支持文字转语音。
本次不自动推 RTMP 流，不下发 SIP 凭据；图片、录音、备份轨迹等尚未接入的 HTTP 上传返回明确失败，
避免让固件以为文件已保存。不能将当前改动表述为视频、文件上传或完整语音链路已验收。
PDF 第 8 页注明登录响应的 `data`、`sip_info` 不能为空；当前没有真实 SIP 服务配置，
因此未发送 `sip_info`。已从该台设备的 `M6811_58` 程序核对：`WsListener` 在
`ca_login.status=true` 后独立设置在线并启动心跳，不检查 SIP；`CapActivity.MsgReciever`
缺少 SIP 时跳过额外的录像和 SIP 初始化。因此基础遥测可独立联调，但仍需实机报文验收，
不填入虚假 SIP 账号，也不将此结论推广为其他固件版本。
最小配置不下发空的 `extra` 配对信息，避免覆盖帽子当前手环绑定；未下发的告警、录像、
升级配置在该固件中会保留原值。

### 实机验收顺序

- 先确认厂家配置方式、设备联网提示、实际 `device_id` 和服务地址可达。
- 在后台登记并发放给正确人员；检查三端设备身份和归属一致。
- 设备上线后核对电量、佩戴变化、室外 GPS、最后上报时间；断网超过 45 秒应退出在线状态。
- 触发一次设备 SOS，核对事件来源为设备、人员/厂站正确，三端看到同一事件和协助记录。
- 恢复网络、再次登录、归还再发放，核对旧连接和旧人员不会覆盖当前状态。
- SIP、广播、视频和文件上传分别配置、单独联调，不能用心跳成功替代这些项目的验收。

后端协议与台账回归入口：

```powershell
mvn -pl ruoyi-admin -am test
```

新增测试使用虚构设备编号与隔离测试状态；协议测试和本机 WebSocket 握手测试不等于真实帽子测试。

2026-10-20 开发验证：后端 196 项测试通过（0 失败、0 错误、0 跳过），
包括实际本机 HTTP/WebSocket 握手，`ruoyi-admin/target/fdc-admin.jar` 打包成功。
日志保留在 `build/direct-helmet-verified.log`。PC 前台 62 项、PC 后台 328 项测试及两端生产构建通过；
安卓相关 27 项回归及修改文件静态分析通过，未执行全仓安卓回归或生成新的安装包。
安卓回归显式开启测试 Mock 以兼容旧测试夹具，其中真实共享接口用例仍显式 `mock:false`。
上述为首轮开发验证；随后 bootstrap 兼容修正完整构建通过 200 项后端测试，
日志为 `build/direct-helmet-bootstrap-verified.log`。固件配对配置保留修正后的 31 项直连回归通过，
日志为 `build/direct-helmet-firmware-verified.log`。已备份并替换日常后端容器、登记这顶帽子的
未领用档案，既有资产保持不变；实机真实登录和基础心跳已接通，SIP 媒体尚未验收。
当时实测运行镜像为 `melhat-backend:helmet-20261020-215502`，后续统一发布见下方安全带验证记录。
另已在源码兼容该固件大写 `Relative_altitude`（仍优先既有小写字段），33 项安全帽回归通过，
日志 `build/direct-helmet-altitude-verified.log`。该次打包同时包含并行开发中的安全带代码，
未据此替换当前已联通镜像；相对海拔兼容待统一验证发布，不纳入本次实机验收。

## 安全带直连（1020 安全带源码协议）

安全带入口为 `/wsBelt` 和 `/api/belt/`，独立于一体帽 `/wsHat`、`/api/`。
依据 `1020源码/安全带/safety_belt_server` 和交付日志实现设备登录、实时状态、定位、设备告警及手动 SOS。
实时登录和上报通过 WebSocket 指向本服务；HTTP 业务地址按设备原链路保留厂家 `http://caps.runde.pro/api/`。

### 登记和启用

1. PC 后台新建“安全带”，接入方式选择“安全带直连”。填写平台编号、实际 `ca_login.device_id`
   对应的“设备登录 ID”、独立的 S/N。遥测的 `imei` 必须与登录 ID 一致。
   登录 ID 与设备类型建立后不随领用、归还改变，不允许跨设备重复身份。
2. 在正确厂站下领用给人员。归属来自本地台账，硬件上报的 `user_id` 不作为授权或人员归属依据。
   未领用设备可以登录并保存设备数据；人员显示为未关联。
3. `.env` 设置以下变量并构建、更新后端。若当前容器来自私有部署清单，应沿用该清单中的环境、
   启动参数和持久卷，仅新增安全带配置；不要用空白 `.env` 覆盖正在使用的账号及数据库配置。

   ```dotenv
   MELHAT_BELT_ENABLED=true
   MELHAT_BELT_PUBLIC_BASE_URL=http://192.168.3.57:18084
   MELHAT_BELT_API_URL=http://caps.runde.pro/api/
   MELHAT_BELT_WS_URL=
   MELHAT_BELT_HEARTBEAT_TIMEOUT_SECONDS=45
   ```

   此例单独指定厂家 HTTP 目录；WS 留空时由 public-base-url 自动生成。以上主机是本次检查的 WLAN IPv4，
   仅适合同一局域网、网络可达的设备；4G 不能使用它。安全帽现有 USB reverse 配置不需改动。

### 厂家平台需要填写的地址

| 网络入口 | HTTP 请求地址（保留末尾 `/`） | 长连接地址 |
| --- | --- | --- |
| 设备和电脑在同一可达局域网 | `http://caps.runde.pro/api/` | `ws://192.168.3.57:18084/wsBelt` |
| 厂家要求的普通 WS 公网入口（已部署） | `http://caps.runde.pro/api/` | `ws://39.106.212.138:80/<安全带私有路径凭据>/wsHat` |

`<...>` 必须替换为真实可访问入口，不能原样填写，也不能使用对接人员的服务器地址来代替自己的入口。
厂家平台选择这台安全带对应的设备号，HTTP 字段保留厂家目录，长连接字段填写我们的完整入口；仍需以实机确认该页面下发配置生效。
后端安全带仍用 `/wsBelt`；公网普通 WS 的私有 `/wsHat` 只是该安全带网关的精确别名，不是安全帽的裸 `/wsHat`。
原 WSS 私有 `/wsBelt` 路径保持支持。不要把 HTTP 目录写成前端网页地址或重复加 `index.php`。

电脑可以作为服务器，但 4G 需要另行建立公网入口：宽带有可入站公网地址时做路由映射，
否则使用支持 WebSocket 的反向隧道/公网转发。当前专用公网入口通过安全带网关 `127.0.0.1:18087`
转发到后端 `18084`，必须支持 WebSocket Upgrade、连接持续时间超过心跳周期；电脑和后端保持运行。
只转发设备接入所需的路径，不开放数据库或 Redis。公网入口变化时同步更新对应 WS 配置；厂家 HTTP 目录独立保留。

如果厂家允许修改设备内置的“获取配置地址”，可使用
`http://<设备可达主机>:<端口>/api/belt/config/index.php?ctl=config&act=get_config`。
固件追加 `device_id`；返回 `data.config` 是 JSON 字符串，含 `api_url` 和 `ws_url`。
设备内置的获取配置地址（bootstrap）和回包中的 HTTP 业务目录 `api_url` 是不同设置；改 `api_url` 不代表已改 bootstrap。
当前安全带网关的两个私有 HTTP 配置端点仅作为 fallback：请求仍到固定本地后端，回包 `api_url` 固定为厂家目录，
`ws_url` 按厂家要求返回固定 `ws://39.106.212.138:80` 加安全带私有 `/wsHat` 路径；云端精确路由及 `2026-10-21T11:02:39Z` 本机网关更新重启均已完成。
它不会向厂家 HTTP 服务转发请求；本地 WS 登录上报也不依赖先访问此 fallback。
不下发空配对字段、升级字段或厂家源码中写死的测试高度阈值。

### 状态语义与实机验收

- 接收 `ca_login`、`ca_report_location`、`ca_sos`、`ca_sip_sos`；保存成功后才 ACK。
  默认断线/45 秒无有效消息即离线。重复登录替换旧连接，旧连接不能继续上报或将新连接置为离线。
- 电量 `bat_l`、原始佩戴 `is_weared`、A/B 钩 `hanger_a_status/hanger_b_status`、
  `IgnoreHookAlarm`、网络信息、`x_point` 纬度/`y_point` 经度进入三端共享数据。
  没有 GPS（0,0）仍接收电量等状态；旧定位保留为陈旧，不能表示当前位置。
- 三种高度分开保留：`Relative_altitude → relativeAltitude`、`Altitude → altitude`、
  `altitude → gpsAltitude`，不照搬厂家服务端将两种高度覆盖的代码；实际物理语义需联调确认。
- 厂家 DTO 将佩戴值写成 1 未佩戴/2 已佩戴，但其 PC/APP 使用 1 已佩戴，挂钩值没有完整定义。
  因此默认展示原始值，已佩戴/已挂钩保持未确认；确认真实固件定义后配置
  `MELHAT_BELT_WORN_VALUE`、`MELHAT_BELT_UNWORN_VALUE`、`MELHAT_BELT_HOOKED_VALUE`、
  `MELHAT_BELT_UNHOOKED_VALUE`。每对值必须非空且不同；未知码、缺失值、超时状态均不判为安全。
- `ca_sos.type` 的厂家 `fd_sos_type` 字典未随源码交付；事件保留原码并标为安全带设备告警，
  不猜成跌落、脱钩等具体含义。手动 SOS 单独记录，但不声称已建立 SIP 通话。
- HTTP 离线轨迹补传、媒体上传、SIP/广播不在本次实时接入范围；返回明确失败，
  不使用厂家写死测试轨迹，不对未保存数据返回成功。
- 验收依次核对实际设备 ID、登录、状态变化、室外定位、告警/SOS的厂站人员归属、断网离线、
  重连、归还再领用。厂家协议的登录仅携带设备 ID；当前公网网关另加专用路径凭据、固定设备白名单及受限转发。

后端回归仍运行 `mvn -pl ruoyi-admin -am test`；新增用例包含交付日志形状的报文、身份隔离、
持久化失败、未知状态、超时、领用归还、去重，以及真实本机 HTTP/WebSocket 握手。

### 2026-10-20 验证与本机部署

- 后端全量 223 项测试通过，0 失败/错误/跳过，其中安全带专用 21 项；JAR 打包成功。
- PC 后台相关 37 项、PC 前台全量 64 项测试通过；最终定位来源改动另跑 9 项回归。
  两端生产构建通过；安卓真实遥测投影 10 项通过，未生成新的安卓安装包。
- 已备份监护状态、保留原有环境/启动参数/数据卷，更新运行镜像为 `melhat-backend:belt-20261020`。
  已实际验证运行服务的 HTTP 配置入口、WebSocket 握手和未登记设备登录拒绝，安全带接入已启用。
  现有安全帽配置仍为 USB reverse 使用的 `http://127.0.0.1:18084/api/` 与 `ws://127.0.0.1:18084/wsHat`。
- 私有部署清单/状态备份位于仓库忽略目录 `output/device-ready/belt-deploy-20261020/`，
  清单含部署环境值，不应公开。回滚可使用原 `output/device-ready/helmet-backup-20261020-215502/deploy-compose.private.json`。
  当前清单使用既有外部数据卷，切勿加 `--remove-orphans` 删除数据库或 Redis 容器。
- 本次没有登记虚构安全带或向日常台账注入真实设备的模拟登录/遥测，没有改变厂家平台的实物设备配置。

### 2026-10-21 安全带公网入口验收

- 已登记实物 `866652023095053`（S/N `JP20260709A0251`）为 `device-13`、`DIRECT_BELT`，归属临江示范电厂 `site-1`；保持库存未领用、未绑定人员。
- 已在 `39.106.212.138` 的 `lingzhiaide.com` 下应用独立安全带入口，事务目录 `/var/lib/belt-gateway-deploy/review-02`。
  通过受限 `belt-tunnel` 账号将云端 `10.255.1.1:28087` 转发至本机 `127.0.0.1:18087` 网关，再到本机后端 `18084`。
- 公网验证于 `2026-10-21T06:24:34.586Z` 通过：HTTP 配置查询 `GetSucc`、返回的公网地址正确，错误设备 HTTP 返回 400、WebSocket 关闭码 1008。
  未用真实设备 ID 模拟 WebSocket 登录；实物接入尚未验证。部署后安全帽仍持续实时上报，现有 HTTPS 网站健康。
- 重新核对厂家源码及 PDF 后，HTTP 字段已恢复为 `http://caps.runde.pro/api/`，长连接改为普通 WS 的固定 IP:80 私有 `/wsHat` 入口；原 WSS 私有 `/wsBelt` 继续支持。厂家平台只修改这两项地址，`2026-10-21T11:09:05.852934Z` 回读均与目标一致，见[配置回读](../../../output/device-ready/belt-deploy-20261020/vendor-config-read-check.json)和[保存记录](../../../output/device-ready/belt-deploy-20261020/vendor-plain-ws-saved.png)。
  本机填写说明 `belt-device-gateway/.local/厂家平台配置.txt` 已同步当前 HTTP/WS 值。WS 完整地址含专用接入凭据，不提交版本库或公开分享。`11:11:25 UTC` 的真实设备状态仍为 `NOT_CONNECTED`；当时尚未收到实物开机确认，后续验证见下文。
- 云服务器当前提供公网转发，业务仍运行在本机；电脑、Docker 后端、安全带网关及 SSH 隧道需持续运行，电脑不能休眠。隧道未安装开机自启。
  启停、回滚及隔离资源说明见 [安全带云端说明](belt-device-gateway/cloud/README.md)。佩戴、挂钩及告警码的未确认含义仍按上文保留为未知，不猜测安全状态。
- 实机排障新增固定枚举诊断：`belt-device-gateway/.local/belt-gateway-events.ndjson` 可区分本地 TCP 到达、HTTP/WS 拒绝、登录帧校验和上游发送阶段，只保存时间、事件、原因及计数；最多 3 × 256 KiB，不保存凭据、设备报文或位置。该阶段网关 43 项测试通过；下述普通 WS 更新后为 44 项。
  公网自检本身会产生配置读取及错误 ID 拒绝事件，必须从自检结束后的静默窗口判断自然流量；`ws_login_forwarded` 仅表示发送完成，仍需后端真实状态确认上线。网关没有收到请求也不能区分云端 TLS 阶段、4G 网络或设备未发起连接。
- 已修复隧道按整个生命周期累计重试次数的问题：稳定运行 120 秒后清零连续短失败预算，短失败重试窗口至少覆盖 5 分钟；保持原有 SSH 限制、严格进程身份校验和安全帽隔离。新增有限轮转事件日志，并显式使用 UTF-8 读取状态，兼容 Windows PowerShell 5.1 的中文工作区路径；8 组隔离测试通过。
- 对交付 `sys-info.2026-10-09.log` 重新审计确认：同一设备 10 次登录后均发送 `getSettingWithDev`，另有 `show_current_battery`；厂家服务保持连接，原网关会拒绝并断开。现仅在登录及身份校验后静默忽略这两个辅助动作，不伪造响应、不转发、不更新心跳或状态。运行网关于 `2026-10-21T09:35:31Z` 已更新，无需重启 Java 后端。
- 厂家配置控制器还提供 `config/index.php`。已补齐网关及云端的精确 `/api/belt/config/index.php` 别名；独立云事务 `/var/lib/belt-gateway-deploy/route-alias-01` 已应用，原 `review-02` 记录保持不变。云脚本当时 36 项隔离测试通过，`09:40 UTC` 直接云服务器 IP 的 TLS 1.2、两个 HTTPS 配置路径及公网 WebSocket 错误身份拒绝验证通过。厂家已保存地址无需因此变更；这些修复不能代替实物接入验收。
- 无 SNI 的 TLS 握手失败已通过 `/var/lib/belt-gateway-deploy/default-sni-01` 事务修复，Caddy 仅新增 `default_sni lingzhiaide.com`；含该补丁共 44 项云隔离测试通过。`2026-10-21T09:59:32Z` 对照确认带 SNI、无 SNI 的 TLS 1.2 均通过 CA 与域名校验，证据见[应用前](../../../output/device-ready/belt-deploy-20261020/tls-nosni-before.json)和[应用后](../../../output/device-ready/belt-deploy-20261020/tls-nosni-after.json)。探针未发送 HTTP 或模拟设备登录，实物登录和上报仍待验证。本阶段之后又应用了下述明文 WS 补丁，完整回滚应先撤销最新事务。

- 明文 WS 精确入口已通过 `/var/lib/belt-gateway-deploy/legacy-ws-01` 的云端 preview/apply，见[应用记录](../../../output/device-ready/belt-deploy-20261020/cloud-legacy-ws-applied.png)；12 项新增及原有 44 项云隔离测试全部通过。Node 网关于 `2026-10-21T11:02:39Z` 更新重启（当时 PID `65236`），44 项测试通过；Java 21 项定向测试修复已上线，挂钩 `-1` 等未知值保留为未知，不再因此拒绝整帧。本地及公网错误设备 ID 验收通过，见[公网证据](../../../output/device-ready/belt-deploy-20261020/public-gateway-evidence.json)。这些检查未模拟真实安全带登录，不能证明实物已接通。当前完整回滚顺序为 `legacy-ws-01` → `default-sni-01` → `route-alias-01` → `review-02`。

### 2026-10-22 已开机后的接入复核

最新实物验证（2026-10-22 UTC）：用户已明确确认安全带已开机；`00:42:39`、`00:43:47`、`00:44:27` 三次检查仍为 `NOT_CONNECTED`，`lastSeen` 和 `telemetryReportedAt` 均为 `null`，未出现真实设备的首帧通过校验或 `ws_login_forwarded`。`00:43:25–00:43:26` 新增网关事件全部来自错误设备 ID 自检，不是实物登录。`00:43:26` 公网网关验收通过，厂家 `caps` 与文档所列 `mg` 引导接口均读回当前 HTTP/WS 地址，但尚不清楚硬件是否实际获取了这些配置。本轮云端浏览器超时，没有有效入站捕获，不能据此判断设备请求是否到达云端。当前结论为已开机但未接通；下一步需要设备端取配置结果、实际连接目标和失败日志。 证据见[最终实物状态](../../../output/device-ready/belt-deploy-20261020/physical-after-confirmed-poweron-20261022-20261022-004427Z.json)、[本轮公网验收](../../../output/device-ready/belt-deploy-20261020/after-confirmed-poweron-0046-public-gateway-evidence.json)、[厂家配置回读](../../../output/device-ready/belt-deploy-20261020/after-confirmed-poweron-0046-vendor-config-read-check.json)和[引导接口对照](../../../output/device-ready/belt-deploy-20261020/after-confirmed-poweron-0046-documented-bootstrap-comparison.json)。
