# 福大国标级联桥 0.1.0

这是面向 GB/T 28181-2022 实时级联的可运行实现。2026-11-05 已使用福大实际参数部署独立云端服务，完成上级注册、目录交互及真实安全帽 H.264/AAC 取流复验。福大端点播、画面和声音验收尚待双方安排，不能表述为已通过完整互通或合规认证。

链路：安全帽 → 原有 RTMP/SRS → 本组件按需拉入 ZLMediaKit → PS/RTP → 福大。业务 Java 负责真机推流与服务租约；本组件负责国标信令、会话和独立媒体转发。现有 FreeSWITCH 通话服务不承担国标级联。安全带不生成视频通道。

## 已实现

- 单一受信上级，SIP UDP 或 TCP；REGISTER、MD5/SHA-256 Digest（qop=auth 或无 qop）、续注册、Keepalive，失败后重新注册。
- Catalog、DeviceInfo、DeviceStatus 查询，只有配置白名单中的 HELMET；设备在线状态读取实际 Java 设备会话。
- 实时 INVITE、SDP PS/90000 协商、等待真实推流与轨道、200/ACK 后开始 PS/RTP；BYE、CANCEL、无 ACK、源流丢失、最长会话超时、进程退出释放。
- UDP RTP 或 TCP 主动发送（福大 SDP 为 setup:passive/actpass）；信令重传不重复申请/启动，错误 dialog tag 不能停止会话。
- 服务租约复用原有 watcher 计数，释放本租约不会停止其他观看者或录像。Java 租约 90 秒，桥每 20 秒续租；桥崩溃后 Java 自动清理，桥启动时重试私有日志中的媒体清理。
- 首次拉流仅对 ZLM 明确的 `play rtmp timeout` 重试：先清理本会话私有代理，在原始取流期限内最多尝试三次；鉴权、连接拒绝、未知错误不重试。真实轨道未就绪时不会返回点播成功。
- 固定上级源 IP/端口、媒体目标 IP 白名单及端口范围；可显式增列仅用于 TCP RTP 的目标端口。SDP/URI 不可提供拉流地址。内部 API 禁止重定向，使用独立带时戳/nonce 的 HMAC；公网参数与媒体口必须配套防火墙。

## 首期能力边界

只提供实时点播。未实现录像回放/下载、PTZ、订阅目录推送、对讲/广播、TLS/SRTP、SM 系列国密鉴权、IPv6、TCP 被动媒体发送、多上级、高可用或完整的 SIP RFC 扩展。收到未支持查询返回 501，未支持方法返回 405，不伪装成功。

视频仅接收已就绪 H.264 轨道，不做转码。本期音频限定为 AAC；默认 `GB_REQUIRE_AUDIO=true`，必须有真实 AAC 音轨才答复点播成功；明确双方接受纯视频后才可设 false。ZLM 禁止自动补静音。本次实机已检出 H.264/AAC，福大已确认支持；对方实际解码播放仍需验收。2022 所需功能集合、证书/鉴权与 SIP 报文细节仍需福大正式互通验收。

## 配置合同

复制 `.env.example` 到私有 `.local/gb.env`，文件权限 0600；示例默认禁用。任何密钥均只经私有环境变量注入。

| 参数 | 含义 |
| --- | --- |
| GB_UPPER_ID / GB_UPPER_IP / GB_UPPER_PORT | 福大 20 位平台 ID、固定 IPv4、SIP 端口 |
| GB_LOCAL_ID / GB_LOCAL_IP / GB_LOCAL_PORT | 本平台 20 位 ID、对外通告 IPv4、信令端口 |
| GB_BIND_IP | 实际监听网卡；默认回环，正式部署按已批准网络调整 |
| GB_REALM / GB_USERNAME / GB_PASSWORD | 福大分配 SIP 域、用户名及密码；不能使用网页登录账号 |
| GB_SIP_TRANSPORT | UDP 或 TCP，双方一致 |
| GB_CHARSET | XML 字符集 `UTF-8` 或 `GB2312`，默认 `UTF-8`；福大本次要求 `GB2312` |
| GB_MEDIA_IP / GB_MEDIA_PEERS | 本端媒体对外 IP、福大媒体接收 IPv4 列表（逗号分隔） |
| GB_MEDIA_MIN_PORT / GB_MEDIA_MAX_PORT | UDP/TCP RTP 目标允许范围，两端包含；福大原约定为 `30010–30050`，RTCP 放行按实际传输方式另行配置 |
| GB_MEDIA_EXTRA_TCP_PORTS | 范围外额外允许的 **TCP RTP** 目标端口，逗号分隔的单独端口号，默认空；仍必须匹配 `GB_MEDIA_PEERS`。不影响 UDP 端口许可 |
| GB_RTP_SOURCE_PORT | 本端源 RTP 基础端口，逐会话递增 2，须为最大并发保留 RTP/RTCP 端口 |
| GB_CHANNELS_JSON | JSON 数组：`[{"channelId":"20位编号","deviceId":"真实设备号","deviceType":"HELMET","name":"安全帽名称"}]` |
| GB_JAVA_ORIGIN / GB_JAVA_SECRET | Java 内部服务 origin（不含路径）、独立 ≥32 字符 HMAC 密钥 |
| GB_ZLM_ORIGIN / GB_ZLM_SECRET | 本地 ZLM API 地址及 ≥32 字符字母/数字/下划线/短横线密钥 |
| GB_SRS_ORIGIN | 唯一受信 RTMP 源 origin，不含应用名/路径/凭据 |
| GB_REQUIRE_AUDIO | 默认 true；不自动补静音，不假设真实帽子一定有音轨 |

福大本次实抓 INVITE 使用 `TCP/RTP/AVP`、`setup:passive`、媒体目标 `175.42.30.194:30003`，并已确认该端口为收流端口。对应配置为 `GB_MEDIA_PEERS=175.42.30.194`、原范围 `30010–30050` 不变、`GB_MEDIA_EXTRA_TCP_PORTS=30003`。仅允许该白名单 IP 的 TCP 30003；UDP 30003、RTMP 30001、RTSP 30002 及 30004–30009 不因此获准。此配置不是改用 RTMP/RTSP 推流，实际链路仍是 SDP 协商的 PS/RTP over TCP。

Java 环境配置：`FUDA_GB_INTERNAL_ENABLED=true`、`FUDA_GB_INTERNAL_SECRET` 与 `GB_JAVA_SECRET` 一致、`FUDA_GB_ALLOWED_DEVICES` 为允许接入的安全帽设备号列表。独立服务认证路由：

- `GET /internal/fuda-gb/v1/devices/{deviceId}/status`
- `PUT /internal/fuda-gb/v1/leases/{leaseId}`，请求 `{"deviceId":"..."}`，创建或续租同一租约
- `GET /internal/fuda-gb/v1/leases/{leaseId}`，实际发布状态及单流播放票据
- `DELETE /internal/fuda-gb/v1/leases/{leaseId}`，幂等释放该租约

认证头为 X-GB-Time（Unix 秒）、X-GB-Nonce（16–100 字符，每次新值）、X-GB-Signature。签名为 HMAC-SHA256 十六进制，内容依次为时间、nonce、大写 HTTP 方法、原始路径、请求字节 SHA256，每项用换行连接。Java 接受 ±60 秒偏差并拒绝 nonce 重放。禁止对外反向代理这一前缀；不使用人类会话 Token。Java→现有媒体控制仍使用原有 X-Media HMAC，不共享两套密钥。

## 本地验证与部署

无需 npm 依赖：Node ≥22.14 执行 `node --test test/*.test.mjs`。测试只使用本机随机端口的假福大 SIP 和假媒体 HTTP 控制，不访问设备或公网；验证控制调用与状态机，不代表真实 PS/RTP 字节或福大播放已验收。

`node server.mjs` 默认禁用，不打开端口。配置具备后，在独立 Linux 媒体主机可使用 `docker compose --env-file .local/gb.env --profile gb up --build`。这是通用部署示例；本次云端使用专门校验的 `compose.video.json`，部署目录 `/home/admin/wearables-fuda-gb-20261105`，更新时应保留其资源限制、固定镜像、文件校验清单及备份。Compose 独立项目名，不重启已有 SRS/FreeSWITCH；ZLM 管理 HTTP 仅监听回环。Java 跨主机必须使用 HTTPS 内部专用入口；HTTP 只允许回环。会话日志需纳入私密备份。

ZLM 固定官方镜像摘要：`sha256:3c98f76c84fe191b3f2411c7378a2b4f4838af4cb2939f12fe1d2c23912ccb26`。本次实际拉取该镜像并离线导入云端，配置内容 ID 为 `sha256:fb4e43c8953e5111ec3ab33eed3434d494f00d1fa064742d4c9405a1aa0513fe`，不使用浮动标签。固定版本已通过本地实际 UDP/TCP PS/RTP H.264/AAC 解码、私有代理清理及冷启动超时恢复测试；该集成测试使用模拟 Java 控制器。升级前复测 getMediaInfo、addStreamProxy、startSendRtp、delStreamProxy 及端口策略。

正式验收至少检查：注册/续期/断线恢复、正确目录映射、离线/忙拒绝、UDP 与 TCP 协商、H.264+真实音轨解码、SSRC/PT、并发共享观看与录像、BYE/CANCEL/ACK 超时、蜂窝掉线、重启清理、非法目标拒绝。本地测试和真实源取流通过不等于福大接收通过；福大实际点播、RTP 接收及停止点播复验仍待完成。

官方依据：[ZLM API](https://docs.zlmediakit.com/guide/media_server/restful_api.html)、[官方配置](https://github.com/ZLMediaKit/ZLMediaKit/blob/master/conf/config.ini)、[官方镜像](https://hub.docker.com/r/zlmediakit/zlmediakit)。
