# 福大数据与国标视频模拟器

在本机模拟福大接收端，接收位置、状态、报警数据，并模拟国标上级平台完成注册、目录、点播和 PS/RTP 视频接收。复用项目现有签名接收器、SIP 工具与国标桥；没有修改正式 Java 业务或部署任何正式服务。

## 启动与使用

Windows 双击本目录 `start-simulator.cmd`，或在本目录执行：

```powershell
node server.mjs
```

打开 **http://127.0.0.1:19091**。默认 HTTP 19091、SIP UDP/TCP 15061，仅监听本机。可用环境变量 `SIM_HTTP_PORT`、`SIM_SIP_PORT` 调整端口；端口占用时会明确报错，不结束其他进程。

1. “数据接收”页点击“发送三类测试数据”，查看位置、状态、报警记录；可筛选类型、查看完整报文。按钮通过真实 HTTP 签名请求进入 `/receive`，没有绕过接收接口。示例观测时间沿用原虚构样例，接收时间和任务创建时间为当前时间。
2. “国标视频”页点击“连接测试安全帽”。使用现有 `GbBridge` 作为合成下级，真实执行 REGISTER 鉴权和 Catalog，不调用实际安全帽、Java 后端或福大服务。
3. 选择 UDP 或 TCP 媒体，点击“开始点播”。可以看到真实接收包数和媒体大小；点击“停止接收”，或等待约 6 秒合成源发送完毕。主机计时精度会影响实际发送耗时。
4. 接收结束后点击“播放回放”，查看接收形成的 MP4；也可下载原始 PS。当前是接收状态实时更新、结束后回放，不提供浏览器实时预览。

数据及录制文件保存在 `.local/`，重启保留。接收数据上限 5000 个事件/64 MiB；单个视频最多 5 分钟或 256 MiB；当前页面一次点播一个通道。不会自动删除已有记录。

## 凭据与现有发送端接入

首次启动自动生成 `.local/config.json`，其中的 `appId/secretBase64` 用于数据测试，`upperId/realm/sipUsername/sipPassword` 用于视频国标测试。该目录已被 Git 忽略；页面和日志不输出密钥。

模拟器使用独立随机测试凭据。用户已经确认的正式“查询与推送复用原 AppId/Secret”配置保持原样，仍为关闭；模拟器没有加载它。

数据发送端在专门的本机测试配置中使用 `http://127.0.0.1:19091/receive`，填写本模拟器的测试 `appId/secretBase64`，并显式设置 `allow-loopback-http: true`。不自动修改运行服务或启用业务推送。接收成功响应为 HTTP 200 和 `{"code":0}`，签名采用现有推送协议。

接入其他本机下级时，关闭模拟测试下级并重启模拟器，按 `.local/config.json` 的上级编号、域和 SIP 认证配置下级；SIP 地址为 127.0.0.1:15061。媒体接收 IP 是 127.0.0.1，每次点播的具体端口在 SDP 中告知；本机测试下级的允许目标端口范围可设为 1024–65535。正式网络、真实凭据和真实设备接入不在此次启动行为中。

## 视频依赖

网页、数据接收和 SIP 使用 Node.js 内置模块，无 npm 依赖。PS 接收本身无需 FFmpeg；生成合成画面/测试音和 MP4 回放需要 FFmpeg。本机已安装到本目录 Git 忽略的 `.local/tools/`。

其他电脑可以指定 `FFMPEG_PATH`，或在本目录安装相同的 FFmpeg 分发包（需要 Python）：

```powershell
py -3.12 -m pip install --no-deps --target .local/tools imageio-ffmpeg==0.6.0
```

程序会发现该包中的可执行文件。缺少 FFmpeg 时会提示原因，已收到的 PS 保留；不会把没有可播放文件的会话显示为播放成功。视频 H.264 保留原编码，音频转为 AAC 供浏览器回放。

## 已实现与边界

- 数据：HMAC 验签、时间窗口、nonce 防重放、eventId 去重与内容冲突检查、本地持久保存；写入失败不返回成功，损坏的历史文件不会静默忽略。nonce 防重放缓存是进程内存，接收器用于本地测试，不作为正式福大服务部署。
- 国标：SIP UDP/TCP、Digest 注册、保活、目录、INVITE/ACK、BYE/CANCEL、超时及会话清理；媒体支持 UDP RTP 与 TCP 被动接收（对接我方 TCP 主动发送）。
- RTP：校验头部、PT96、SSRC、扩展与填充；记录序号缺口，丢弃重复/迟到包，不实现丢包重传或乱序重排。
- 演示视频是真实传输、保存并解码的合成画面和测试音；不代表安全帽实机、福大平台或完整国标合规认证已通过。

## 验证记录

2026-11-02：本模块测试、增强后的数据接收器测试、既有国标桥回归合计 **57 项通过，0 失败、0 跳过**。包含真实 FFmpeg H.264+MP2 PS 输入、UDP/TCP 媒体接收、H.264+AAC MP4 输出与解码验证。

在 `local-dev` 下运行（先把 `FFMPEG_PATH` 指向有效程序；未设置时媒体实测用例会明确跳过）：

```powershell
node --test fuda-push/mock-receiver.test.mjs fuda-simulator/*.test.mjs fuda-gb-bridge/test/*.test.mjs
```

浏览器已操作并回读：三类数据入库、报警筛选及报文详情、重启后记录保留、国标注册与目录、UDP 点播自然结束、TCP 点播手动停止、两种接收结果的实际回放。回放尺寸 640×360，浏览器 `readyState=4`、无媒体解码错误。

本轮没有改动 Java 业务代码，因此未重复运行先前已通过的 547 项 Java 全套测试。正式推送仍关闭，原有服务及用户修改保持不变。

## 代码变更说明

| 文件/类 | 方法/函数 | 作用 |
| --- | --- | --- |
| `../fuda-push/mock-receiver.mjs` | `createReceiver` | 复用原签名接收流程，增加可选落盘、历史恢复、统计和模拟器页面入口 |
| `../fuda-push/mock-receiver.test.mjs` | 7 项接收行为用例 | 重试去重、损坏历史、刷新落盘失败后的安全重试 |
| `server.mjs` | `startSimulator`、本地 HTTP 路由 | 页面、状态、合成数据发送、视频控制、录制文件范围读取及关闭 |
| `sip-upper.mjs` / `UpperPlatform` | `start/snapshot/catalog/play/stop/close` | 国标上级注册认证、点播信令、会话与接收器生命周期 |
| `rtp-receiver.mjs` | `createCapture/snapshot/close` | UDP/TCP 解包、PS 留存、资源限制、MP4 转换与元数据 |
| `demo-source.mjs` | `createDemoBridge` | 使用现有国标桥发送合成媒体，不接入实际设备或业务库 |
| `index.html` | `refresh/action/controls`、页面事件处理 | 数据查看、国标状态、点播/停止、接收记录和浏览器回放 |
| `server.test.mjs`、`sip-upper.test.mjs`、`rtp-receiver.test.mjs` | 35 项模块与集成用例 | HTTP 控制边界、信令异常、实际媒体传输及关闭清理 |
| `.gitignore`、`start-simulator.cmd` | 无具体方法 | 排除私密凭据/数据/工具；Windows 启动入口 |
