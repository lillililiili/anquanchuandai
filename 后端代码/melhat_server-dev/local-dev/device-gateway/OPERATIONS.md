# 单顶安全帽设备网关

此独立 Node 服务只服务已登记的一体帽，复用现有后台与数据库。2026-10-21 03:48 UTC 已将实机引导地址切到北京云服务器的 HTTPS 入口，并移除 USB 网络转发。随后用户物理拔线，真实 4G 上报仍持续更新，三端 API 均显示 ONLINE / CURRENT。定位修复镜像为 `melhat-backend:gps-20261021t055746z`，基于原安全带镜像仅替换安全帽解析类，保持其他程序、环境、端口和数据卷。

当前链路：安全帽 4G → `lingzhiaide.com`（`39.106.212.138`）HTTPS/WSS → 云端专用转发 → 本机 `127.0.0.1:18086` → 后端 `127.0.0.1:18084`。电脑、Docker 后端、网关和 SSH 转发必须保持运行；没有配置开机自启动。路由器、VPN、云防火墙和现有知识库业务没有调整。

## 安装、检查与运行

需要 Node.js 22 或以上。依赖通过官方 npm registry 锁定为 `ws@8.22.0`，提交的 `package-lock.json` 含完整性校验。

```powershell
npm.cmd ci --ignore-scripts --no-audit --no-fund
npm.cmd test
npm.cmd run init:config
```

`init:config` 只创建被 Git 忽略的 `.local/config.json`，使用 32 字节加密随机数生成路径凭据。已存在配置不会被覆盖。终端不输出凭据或带凭据的 URL。

本地配置中的 `publicOrigin` 初始为 `.invalid` 占位域名；在确定真实 HTTPS 公网入口后，仅修改该项，保留路径凭据。占位域名不能通过配置检查。其余默认值为：监听 `127.0.0.1:18086`，上游 `http://127.0.0.1:18084`，设备 ID 固定为已登记实物。

```powershell
npm.cmd run check:config
npm.cmd start
```

`check:config` 不启动监听。`start` 只监听本机回环端口，不会创建隧道。公网 HTTPS/WSS 仅转发到网关端口，不直接开放 18084、管理页面、MySQL 或 Redis。云端配置和按需启动/停止 SSH 的方法见 [cloud/README.md](cloud/README.md)。WSS 使用设备系统信任且匹配域名的完整证书链。

设备引导地址结构为 `publicOrigin/pathToken/api/index.php?ctl=config&act=get_config`。须在本机从配置组合地址并直接写入受保护文件或设备，不在日志、终端或聊天打印真实地址。固件会追加设备 ID 和版本属性；网关返回同一秘密路径下的 API 目录及 WebSocket 地址。

## 支持的协议

- HTTP 精确允许秘密路径下的 `GET /api/index.php`。必需查询字段为 `ctl=config`、`act=get_config`、本帽 `device_id`。实机 M6811_58 追加的 `app_version`、`ic`、`ca_ver` 可选，按标准 query 编码解析，允许空、限制长度且禁止控制字符；它们校验后丢弃，不转发、不记录。`ic` 是系统属性，并非 ICCID。
- bootstrap 从既有后端读取配置，保持 `data.config` 为 JSON 字符串，改写 `api_url`（目录末尾 `/`）和 `ws_url`，删除 `extra`，不更改腕带等配件配置。
- 该 API 路径的 POST 上传明确返回 HTTP 501 与 `status=false`；其它方法、路径和参数拒绝，不提供通用反向代理。
- WebSocket 只允许秘密路径下 `/wsHat`。首条文本 JSON 必须是本帽 `ca_login`，通过后才连接本机后端。支持 `ca_login`、`ca_report_location`、`ca_sos`、`ca_sip_sos`；实机周期心跳为 `ca_report_location`。后续异设备 ID、二进制消息或未知动作拒绝。同设备登录重试允许。
- 消息上限 64 KiB、待连接队列 64 KiB/8 条、发送缓冲 256 KiB、最多 4 条连接、每连接每秒 20 条消息；鉴权与上游握手超时 5 秒、空闲 90 秒。两端断开或失败时成对清理。

## 验证和停止

`npm.cmd test` 当前包含 25 项隔离测试，覆盖实机查询参数、严格入口、设备身份、转发顺序、JSON 规范化、无效/超大/超时上游、连接及消息上限、关闭清理，以及默认关闭、最多12条的脱敏定位诊断。上游均为测试自建随机回环端口；测试模式明确拒绝日常 18084，没有向真实后端发送模拟设备数据。

实机证据保存在被忽略的 `.local/`：`public-preflight.json`（正确 bootstrap 与错误设备拒绝）、`helmet-cloud-switch.json`（地址回读与 USB 转发移除）、`three-end-4g-evidence-final.json`、`helmet-after-physical-unplug-20261021T052245Z.json`（用户物理拔线后两次真实上报）。ADB物理设备已消失，实机仍通过蜂窝公网持续在线。佩戴检测、卫星定位精度、移动轨迹、SOS、视频与对讲尚未完成实测验收。

## 室内位置修复与显示

实机12条脱敏采样确认：`gps=6`、`gps_level=-1`、`c_accuracy=0`、`c_trust=3`，同时携带合法非零经纬度。旧解析把卫星精度未知当成所有定位无效，误丢了基站坐标。修复允许 Wi-Fi/基站类型5/6的该精度状态，保留坐标范围及0,0检查，并拒绝类型4/9缓存刷新位置时间。协议回归10项通过。

`gps-three-client-evidence.json` 记录修复后三端API均有合法且一致的坐标，位置上报时间推进；`gps-report-diagnostics.jsonl` 只记录质量字段和坐标布尔特征，不含精确坐标。前台总览“真实穿戴设备”可展开设备上报位置；后台设备档案“接入摘要”和安卓设备详情也已补相同字段。安卓已安装应用须更新构建后才有新显示区域。

2026-10-21 06:30 UTC 的最终两次检查确认安全帽在线、电量84%，三端位置一致，上报时间从06:29:58推进至06:30:18。期间曾出现隧道断连，不能据此宣称全程无中断。用户确认后，云端专用账号已启用30秒/3次保活；本地重连改为连续短失败计数，受控重启后首次连接成功并于06:30:37 UTC达到60秒稳定期。稳定期仅证明SSH进程存活，业务状态以实机报文为准。

PC两端构建、共享位置逻辑测试、安卓源码分析及相关测试均通过。新安卓debug APK因Flutter引擎及Android测试依赖下载的TLS错误未构建成功，未安装；旧APK不是本次产物。构建日志在 `android代码/melhat_android-main/build/verification/location-device-x64-debug-build.log`。

`locationReportedAt` 是接收位置报文的时间，不是设备测量时间。固件会重报缓存值且没有可信测量时间；同点重复既不能证明移动定位正常，也不能证明定位失效。用户本次在室内且暂时无法室外测试，因此目前仅验证基站位置接收与显示，不能宣称高精度GPS或移动跟随已验收。

定位补丁、原始JAR、私有运行配置及回退Compose位于仓库忽略目录 `output/device-ready/helmet-location-20261021T055746Z/`。仅更新backend时使用其中已核对的回退配置，不恢复数据库、不覆盖安全带变更。

停止网关用 Ctrl+C；停止 SSH 转发后公网设备路径无法到达本机。云端账号和路由的完整回滚见 cloud/README.md。切换前的帽子地址已备份到 `.local/helmet-url-before-cloud.txt`，恢复 USB 模式还需重新建立 `adb reverse tcp:18084 tcp:18084`。该过程不需要回滚后端镜像或数据库。
