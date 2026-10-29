# 安全帽自有云媒体服务

部署目标固定 `39.106.212.138` / `https://lingzhiaide.com`。Java 后台仍在本机 18084；原安全帽 18086、原安全带 18087 不迁移。此目录新建独立 Compose 项目 `helmet-media`，不复用 `dongying-qa-video`。

## 当前验收边界

代码提供 FreeSWITCH SIP/TCP 与 WebRTC、SRS 6 RTMP/WHEP/HLS、coturn、离线中文 TTS、照片/视频存储和按需 FFmpeg 平台录像。`health.ready` 只说明组件可用；设备 SIP 注册、实际音视频接通、相机拍照返回、真实 4G 手机访问必须分别实测。未取得云端 health 前，Java 的媒体开关保持关闭。

本轮实际固件 `RundeCapSip_m6811runde.apk` 的 `classes2.dex` 与《对接设备端接口文档250916》22–29 页一致：

- 图片 `POST api/index.php?ctl=image&act=save_image`，multipart `file`；成功回 `{status:true,data:{url}}`，随后 `report/add_image` JSON 绑定和 `ca_upload_photo` WS 通知。
- 本地视频 `POST api/upload?device_id=...&X-Progress-ID=...`，multipart `file`。成功 ACK 后固件会删除本地文件，因此云端完成写盘和索引持久化后才确认。
- 列表与上传开始回执为 `push_to_client`、`talkback_id`、`res`，列表项是 `file_name` / `file_md5`。网关仅接收与此前下行事务匹配的回执。
- `server_push_upload_video.file_list` 必须发送文件名数组，固件找到本地文件后自行计算 MD5；列表时间范围使用 `yyyyMMddHHmmss`。
- 离线轨迹 `POST api/index.php?ctl=lowcaps&act=ca_backup_data`，JSON `device_id,data`，数据是 `epoch秒,纬度,经度;…`。单次 512 KiB / 10000 点，原样转本地事务接口。只有全部落库后返回 `status:true`；固件收到 true 会清空离线文件，失败必须保留。历史点不冒充当前定位。
- 长视频使用磁盘缓冲，单次 HTTP 上限 256 MiB，超限明确失败并保留设备文件；不在内存缓存整段视频。
- 广播字段 `message` 是音频 URL，故中文文本先在自有云离线合成 MP3，再下发。

## 部署包

在此目录运行 `node init.mjs`，然后 `python cloud/prepare-local.py`。输出在被 Git 忽略的 `.local/`：

- `helmet-media-source.tar.gz`：服务源码、镜像构建配置、预检和回滚脚本。
- `helmet-media-private.tar.gz`：本项目媒体密钥和专用隧道公钥。仅上传授权服务器；不得发入群聊或 Git。SSH 私钥始终保留 Windows 本机。
- `package-manifest.json`：两个包的长度和 SHA-256。

将两个包上传到云端 `/home/admin/` 后执行：

```sh
sudo install -d -m 700 /opt/helmet-wear
sudo tar -xzf /home/admin/helmet-media-source.tar.gz -C /opt/helmet-wear
sudo tar -xzf /home/admin/helmet-media-private.tar.gz -C /opt/helmet-wear
sudo sh /opt/helmet-wear/helmet-media/cloud/install.sh
```

脚本先核对实际公网 IP、空闲内存、磁盘、端口、现有 Caddy 挂载和网站，再备份。原 Caddy 文件按原 inode 增量加入路由；仅 reload，失败自动恢复本次写入。原 helmet/belt 路由保留，安全帽增加同一随机私有入口下精确 `/api/upload`。SSH 新增 `wear-api-tunnel`，只可转发 `10.255.1.1:28088`，不能 shell/SFTP；既有管理和设备账号策略必须逐字一致。

镜像构建与中文模型下载需要官方 GitHub/Docker Hub/Debian/PyPI 可达。FreeSWITCH 从官方源单任务编译 1.10.12，启用 mod_av、VPX 和视频会议转码，不依赖付费包仓库。构建失败时不会替换已有业务。按本轮单安全帽试运行预留至少 1800 MiB 可用内存、1024 MiB 空闲 swap 及 16 GiB 磁盘。TTS 每次请求启动独立工作进程，合成后退出释放模型内存，空闲时不常驻大模型；视频转码并发需另测。

安全组仅增加 TCP `1935,5060,3478`，UDP `3478,8000,16384–16583,49160–49200`。HTTPS/WSS 复用 443。`18190,18192,1985,8080,8021,5066,28088` 不开放公网。若服务器本机防火墙启用，也按这些媒体端口放行，不关闭防火墙。

成功后本机启动 `wear-api-gateway/gateway.mjs`（127.0.0.1:18088）及该目录 `cloud/tunnel.ps1 -Action Start`。公网只开放经过方法和路径白名单检查的 `/api/guardian/v1` 手机业务，沿用 Java `X-Wearable-Token` 会话及权限，不暴露整个 18084、后台管理、数据库或快照接口。

回滚：`sudo sh /opt/helmet-wear/helmet-media/cloud/rollback.sh`。仅撤销本事务管理的新增路由/账号并停止 `helmet-media` 服务；如原配置随后被别人修改，脚本拒绝覆盖，保留记录和媒体文件。

## Java / Node 控制合同

所有控制 API 完整路径 `/helmet-media/control/v1/...`，Caddy 不剥前缀。响应 `{code:200,data:...}`。HMAC-SHA256 小写十六进制，头 `X-Media-Time`（Unix 秒）、`X-Media-Nonce`、`X-Media-Signature`；签名原文为 `time\nnonce\nMETHOD\n完整路径含query\nsha256(raw body)`。90 秒时效、防 nonce 重放。文件上传另发送已签入原文的 `X-Media-Content-Sha256`，先验证签名再接收字节，并流式复核摘要。

| 方法与后缀 | 合同 |
|---|---|
| GET `/health` | configured、ready、components、devices；registered 是真实 FS 注册表结果 |
| PUT `/accounts/{sipId}` | password、kind、deviceId；operator 必须有 expiresAt 和 roomId，最长24小时。返回 sipHost、wssUrl、iceServers |
| POST `/calls` | callId、roomId、participants、video。返回 target、status、connectedDeviceIds |
| GET/DELETE `/calls/{id}` | 实际状态/请求挂断；挂断失败保持 ending，经 ESL 事件或 uuid_exists 确认后 ended；未知 ID 幂等 ended |
| POST `/streams` | deviceId、sessionId；返回 streamId、pushUrl、whepUrl、hlsUrl、expiresAt |
| GET/DELETE `/streams/{id}` | 查询实际 SRS publishing/statusVerified 并刷新 URL / 终止流 |
| POST `/tts` | text、requestId；返回 audioUrl，失败不产生广播成功记录 |
| POST `/recordings`；GET/DELETE `/recordings/{id}` | 已 publishing 的 streamId、requestId / 持久状态 / 结束录像；最终资产验证并持久化后 ready。重启遗留录像标为 interrupted，发 recording.failed |
| GET `/events?after=...&limit=...` | events 数组，含 sequence、type、createdAt；call.connected/ended/failed 与当前 connectedDeviceIds |
| GET `/assets?deviceId=...` | assets 数组，重新签发短期访问 URL |
| POST `/device-upload?...` | Node 网关签名后的 multipart 持久化上传；支持 progressId 幂等 |
| POST `/photo-bind` | deviceId、imageUrl、latitude、longitude；只可绑定该设备已落盘的云照片 |

operator 每次注册和每次拨号都核对有效期/room，禁止任意外呼。播放/文件 URL 是有期票据。FreeSWITCH/SRS 内部回调不经过公网 Caddy，另带私有 hook 密钥。

录像 `recording.ready` / `recording.failed` 事件同时带 `requestId`、`recordingId`、`deviceId`。主动挂断是 `ending` 请求状态；ESL 失败、起呼结果不明和迟到应答都不会提前宣称 ended，避免平台错误释放设备相机。

官方依据：[FreeSWITCH SIP/WebRTC](https://developer.signalwire.com/freeswitch/users-and-endpoints/webrtc-sip/)、[SRS 6](https://ossrs.io/lts/en-us/docs/v6/doc/webrtc)、[离线中文模型](https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/vits.html)。
