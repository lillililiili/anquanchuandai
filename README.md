# anquanchuandai

日常启动入口（在项目根目录运行）：

```powershell
.\scripts\start-wearable.ps1 -CheckOnly  # 只核查当前状态
.\scripts\start-wearable.ps1             # 启动缺失服务，复用已确认归属的运行进程
# 暂不使用安卓时增加 -SkipAndroid；其他模拟器可用 -DeviceId emulator-5556 指定。
```

请先打开 Docker Desktop 和雷电模拟器。入口使用本机已有 PowerShell 7；从 Windows PowerShell 5.1 调用时会自动转交，避免既有隧道状态文件中的中文路径被按ANSI误读。脚本恢复现有 `melhat-mysql`、`melhat-redis`、`melhat-backend`，前台5191、后台5181、安全帽网关18086、安全带网关18087及各自已有SSH隧道，并打开模拟器中已安装的智能穿戴应用、恢复18084转发。配置、密钥及容器必须已经存在；不会重建容器、重装应用或设置开机自启。端口或进程身份冲突时会停止脚本并报告，不结束占用进程。启动摘要和新页面/网关日志在 `output/runtime/start-wearable-*`，隧道继续使用各自 `.local` 下原有状态和日志。`-CheckOnly` 不启动服务、不创建启动日志；`ready` 仅表示这些服务正在运行，不代表真实设备在线或功能验收通过。

当前本地候选版：**三端待真实设备联调版** `device-ready-20261007`。

[版本说明、账号与验收清单](新版安卓端开发/开发任务拆分/三端待真实设备联调版.md)。安卓、PC 前台、PC 后台共用当前 Spring 后端；真实设备效果尚待联调。源码与验收说明纳入本地 Git，构建包、缓存、账号密码及数据库备份保留本机。

2026-10-20 新增一体式安全帽直连适配，参考 `1020源码/安全帽` 的 `/wsHat` 协议，覆盖登记、状态、定位和 SOS 三端同步。配置与实机验收步骤见[一体帽接入说明](后端代码/melhat_server-dev/local-dev/README.md#一体式安全帽直连1020-安全帽源码协议)。已备份并更新日常后端，登记 RD-D1+ 实机档案，确认帽内服务器地址文件，并通过 USB 接通真实登录和持续基础心跳（电量、佩戴状态）。公网/4G、有效定位、SOS 和 SIP 媒体仍需逐项验收。上述冻结版本文件保持不变。

2026-10-20 新增安全带直连适配，独立入口 `/wsBelt`、`/api/belt/`，支持设备预登记、领用归属、实时状态/定位、设备告警和手动 SOS 三端同步。后端 223 项测试通过，已备份并更新本机后端为 `melhat-backend:belt-20261020`。2026-10-21 已登记实机 `866652023095053` 到临江示范电厂（site-1），保持未领用；已开通 `lingzhiaide.com` 下的独立 HTTPS/WSS 入口并通过公网网关验收，现有网站及安全帽持续正常。厂家平台完整地址保存在本机忽略目录 `后端代码/melhat_server-dev/local-dev/belt-device-gateway/.local/厂家平台配置.txt`。详见[安全带接入说明](后端代码/melhat_server-dev/local-dev/README.md#安全带直连1020-安全带源码协议)及[云端运行说明](后端代码/melhat_server-dev/local-dev/belt-device-gateway/cloud/README.md)。用户已保存厂家地址，配置接口读回一致；已按同一实物交付日志修复登录后辅助动作导致断连，补齐云端精确配置路径，并应用 `default-sni-01` 修复缺少 SNI 时的 TLS 握手失败。`09:59:32 UTC` 对照确认带 SNI、无 SNI 均通过 CA 与域名校验。实物登录和上报仍未验证，公网及 TLS 检查不能证明设备已经连接。
