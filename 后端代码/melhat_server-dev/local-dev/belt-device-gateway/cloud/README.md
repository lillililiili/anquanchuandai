# 安全带独立云端入口

华能睿维 HNRW-AQD1 安全带的独立云端入口已通过 `review-02` 事务应用，后续 `route-alias-01`、`default-sni-01`、`legacy-ws-01` 及 `short-ws-01` 均已部署。本地网关于 2026-10-26 UTC 更新短路径兼容代码，当次 PID 为 `40908`；设备协议号与硬件序列号保留在本机私有登记资料中，不能混用。`2026-10-26 02:45 UTC` 已验证实物真实登录和持续遥测，三个后端接口均为 `online=true`、遥测 `CURRENT`，最近上报为 `02:44:48 UTC`，电量 100。本次不包含所有业务功能或长期稳定性验收。

本轮处理过程（2026-10-26 UTC）：厂家先把启动配置正文精简为 916 字节，实物日志确认配置解析成功及 TCP 连接成功。随后发现设备 WebSocket 握手被截断：完整请求应为 205 字节，实际仅发 199 字节，停在 `Upgrade: websock`。独立 `short-ws-01` 事务完成预览和应用后，在现有明文入口增加 24 字符精确路径，将完整握手缩至 186 字节；云端 75 项、本机网关 49 项隔离测试通过。厂家平台改为短地址后，实物收到的配置正文再缩至 897 字节，完成 HTTP 101、业务登录与遥测上报。证据见[三接口核对结果](../../../../../output/device-ready/belt-deploy-20261020/three-client-state-20261026-024315Z.json)，详细实物日志时序见下文。

云端 `review-02` 已返回 `APPLY OK`，部署脚本 SHA-256 已核对为 `fc071ba268b039a793d535ce781ee03d9dde4634068b8ea7a5e4e6f652254fa6`，并通过 24 项云部署测试。公网验证于 `06:24:34.586 UTC` 成功：只读配置获取与返回的公网地址检查均通过，错误设备 ID 的 HTTP 请求返回 `400`，WebSocket 以 `1008` 关闭；安全带隧道首次连接成功。实际事务目录为 `/var/lib/belt-gateway-deploy/review-02`，私有 settings 保存在 `/root/belt-deploy/cloud-settings.json`（600）。以下 preview/apply 命令记录本次事务，不应重复执行；回滚使用同一 `review-02` 目录。既有安全帽配置保持原样，安全带 SSH 也配置了 `ClientAliveInterval 30`、`ClientAliveCountMax 3` 以清理断线转发。

目标为既有服务器 `39.106.212.138`、域名 `lingzhiaide.com` 和 Caddy 容器 `knowledge-base-gateway-1`。保留现有网站、全部其他站点以及安全帽入口。不要运行相邻 `device-gateway/cloud` 下的安全帽部署脚本来添加安全带。

设备继续向固件内置的厂家引导接口取配置；厂家平台的 HTTP 请求地址 `api_url` 保留 `http://caps.runde.pro/api/`，用于后续 HTTP 业务。它与开机引导接口是两个不同概念。当前厂家长连接已按普通 WS 配置：安全带 4G → WS Caddy 精确入口（公网 IP:80，私有 `/wsHat` 路径）→ 云宿主桥网 `10.255.1.1:28087` → SSH 反向转发 → 本机 `127.0.0.1:18087` 安全带网关 → 本机 `127.0.0.1:18084` 后端。云 Caddy 在桥网容器中，不能把容器的 `127.0.0.1` 当成云宿主机的回环地址；`28087` 是桥网转发端口，不是已开通的公网设备端口。

## 独立资源和路径

| 项目 | 安全带值 |
| --- | --- |
| SSH 用户、组 | `belt-tunnel` |
| 专用用户目录 | `/var/lib/belt-tunnel` |
| Caddy/SSH 托管标记 | `BELT DEVICE GATEWAY` |
| 云监听点 | `10.255.1.1:28087` |
| 本地目标 | `127.0.0.1:18087` |
| 本地公钥文件 | `../.local/belt_tunnel_ed25519.pub` |
| 本地主机校验文件 | `../.local/known_hosts` |
| 本地隧道状态 | `../.local/belt-tunnel-process.json` |
| 原部署云事务目录 | `/var/lib/belt-gateway-deploy/review-02` |
| 最新短路径事务目录 | `/var/lib/belt-gateway-deploy/short-ws-01` |

原 `review-02` 只匹配 `/<完整私有路径凭据>/api/belt/index.php` 和 `/<完整私有路径凭据>/wsBelt`，当前另含下述精确配置别名与 WS 短路径。不剥离 URI，由本地安全带网关验证完整路径并转发；不公开 `/api/admin/`、`/api/guardian/` 或整个后端。厂家 HTTP 配置应填 `http://caps.runde.pro/api/`，当前接收服务首选长连接为 `ws://39.106.212.138:80/<原凭据前24字符>/wsHat`；原完整凭据的明文 WS 和 HTTPS/WSS 入口仍保留。厂家平台填写后必须重新读回及验证实物获取，不能从网关部署状态推断厂家配置已保存。本地完整凭据的配置路径保留给旧缓存客户端及诊断，回包返回厂家 `api_url` 与短 WS 地址；它只实现配置查询，不是通用 HTTP 业务入口。不得把示例占位符当成真实地址。

上述为已应用 `review-02` 的原始两条路径。本目录新版 `deploy.py` 为后续全新部署增加第三条精确路径 `/<私有路径凭据>/api/belt/config/index.php`，兼容厂家服务源码中的 `config/index.php` 配置路由。现有部署已通过独立 `route-alias-01` 事务应用该别名，公网配置请求返回 200；不能重跑原部署来更新路由。

安全帽继续使用自己的凭据、`helmet-tunnel`、云端 `28086` 和本机 `18086`；本目录不读取或修改其私钥、状态文件或进程。安全带路径凭据必须与安全帽不同。

## 本地准备与隔离测试

从本目录运行：

```powershell
python -m unittest discover -v
python prepare_local.py
```

测试使用临时目录和模拟 Linux/Docker 命令，不访问云端。若运行环境的系统临时目录不可写，可给 Python 的 `tempfile.tempdir` 指定本工作区内可写目录后再运行 unittest。

`prepare_local.py` 从安全带网关 `../.local/config.json` 读取 `pathToken`，从 `../.local/belt_tunnel_ed25519.pub` 读取公钥，生成 `../.local/cloud-settings.json`。配置应由本地网关初始化流程生成，并使用 32 字节随机路径凭据；脚本只读取公钥，不读取或上传 SSH 私钥。已有输出会拒绝覆盖。私有配置、候选 Caddyfile 和诊断日志不能粘贴到聊天或提交版本库。

服务器脚本使用 Python 3.6 标准库，需要 root、Docker、systemd、OpenSSH 及用户管理命令。沿用锁定密码的专用系统用户，因此要求现有 `UsePAM yes`。不支持所需 SSH 限制的服务器会在预检中失败，不应删减限制绕过。

## 云端预览

由获授权的操作者将 `deploy.py` 上传至新的 `/root/belt-deploy/`，目录权限 700，文件权限 600。预览不需要私有 settings，每次使用新的安全带事务目录：

```sh
sudo python3 /root/belt-deploy/deploy.py preview --state-dir /var/lib/belt-gateway-deploy/review-02
```

预览检查现有 HTTPS 网站、Caddy 单文件挂载 inode、SSH 服务、桥网和端口、专用用户/组/目录不存在。它严格识别已经部署的安全帽主域区块，在其后、网站 fallback 前插入安全带区块；原安全帽和其余站点逐字保留。不同基线会明确拒绝，需要先审阅当前配置，不能用此脚本覆盖不同站点结构。

候选文件会接受实际 `caddy validate`、`sshd -t/-T` 检查，并比较 `root`、`admin`、`helmet-tunnel` 的有效 SSH 策略不变。只在私有事务目录保存候选、原件和哈希，不改活动配置或创建账号。服务器输出仅含状态和非敏感路径。

## 应用已审阅的事务

将安全带私有 `cloud-settings.json` 上传至同一 root 私有目录。使用与预览完全相同的 `deploy.py` 和事务目录：

```sh
sudo python3 /root/belt-deploy/deploy.py apply --state-dir /var/lib/belt-gateway-deploy/review-02 --settings /root/belt-deploy/cloud-settings.json
```

应用会再次检查基线内容、inode、权限、属主、服务和端口，先归档备份，再创建 `belt-tunnel`。账号仅准公钥认证及指定监听点的远程 TCP 转发，禁 shell/SFTP、Unix socket 转发、TUN；限制生效后才安装公钥。既有 SSH 账号公钥保持不变。

Caddyfile 和 sshd_config 在原 inode 写入，只 reload，不重启容器或后端，不改防火墙。桥网端口不应另行开放到公网。`PermitListen` 限制的是云监听点，不能限定私钥持有者在其客户端选择的转发目标，需保护独立私钥。

同一状态目录的重复 preview/apply 会拒绝，避免覆盖备份或重复创建资源；全局锁禁止并行安全带部署事务。已有任何同名专用账号不会被接管。失败会尝试本事务回滚；遇到后续外部修改会保留并报告，不能误报回滚成功。

## 本地隧道

先确保安全带网关已监听 `127.0.0.1:18087`。通过可信云控制台核对 SSH 主机公钥，并将已核对的记录写入安全带 `../.local/known_hosts`。从安全带网关根目录执行：

```powershell
.\cloud\tunnel.ps1 -Action Start
.\cloud\tunnel.ps1 -Action Status
.\cloud\tunnel.ps1 -Action Stop
```

脚本固定使用 `belt_tunnel_ed25519` 与严格主机密钥验证，转发 `10.255.1.1:28087:127.0.0.1:18087`。它不会启动网关或后端；隐藏工作进程在断线后每 10 秒重试，连续 31 次不足 120 秒的短连接失败后才停止（即时失败时仍有 30 个重试间隔，共 5 分钟）。SSH 子进程连续存活满 120 秒就将连续短失败计数清零，此后的断线重新使用完整预算；该存活判据不等于公网可达或实物在线。`Status` 中 `totalAttempts` 与兼容字段 `attempts` 始终保留本次 worker 生命周期内的累计次数，`consecutiveShortFailures` 是当前预算计数，`connectionStable` 表示当前 SSH 子进程是否已达到 120 秒；预算耗尽显示 `retry-budget-exhausted`。不安装开机自启。停止时核对 PID、创建时间、完整命令行、父子进程关系，仅终止本脚本的安全带隧道，保留安全帽隧道。

`../.local/belt-tunnel-events.jsonl` 保存固定字段诊断事件：UTC 时间、事件名、SSH 存活秒数、退出码、故障类别、累计次数和连续短失败次数。单文件最多 128 KiB，另保留 `.1`、`.2` 两份轮转，总计最多 384 KiB；不记录私钥内容、路径凭据、URL、原始报文或异常文本。分类只区分短连接退出、稳定连接结束和主动停止；仅凭退出码不能认定是网络、鉴权还是远程端口占用。原有 SSH stderr 仍仅供私下排障，不应直接粘贴到聊天。

可运行 `powershell -NoProfile -File .\cloud\test_tunnel.ps1` 检查重试边界、连续预算重置、事件轮转和严格进程清理；测试只启动隔离的短时 PowerShell 睡眠进程，不启动 SSH 或连接网络。脚本更新不会修改已运行 worker 的内存代码，需要操作者在合适时间显式 Stop/Start 后才生效。

脚本或 SSH 显示运行不等于设备上线。先验错误路径/错误设备拒绝，再由真实安全带产生 `ca_login`、`ca_report_location` 验收。电脑、Docker、网关和隧道需要持续运行，不能休眠；不向日常后端注入伪造实物心跳。

## 已部署 review-02 增加配置路径别名

先由操作者更新本地网关，使两条配置路径使用相同校验，再将 `route_alias.py` 和本目录新版 `deploy.py` 一同放入新的 root 私有目录 `/root/belt-route-alias/`（目录 700、文件 600）。`deploy.py` 在这里仅作为补丁的共享辅助模块。保留 `/root/belt-deploy/deploy.py` 的原部署版本及原 SHA-256；不要覆盖原脚本或更改 `/var/lib/belt-gateway-deploy/review-02` 中的任何记录。补丁不需要复制私有 settings。

```sh
sudo python3 /root/belt-route-alias/route_alias.py preview --deployment-state /var/lib/belt-gateway-deploy/review-02 --state-dir /var/lib/belt-gateway-deploy/route-alias-01
sudo python3 /root/belt-route-alias/route_alias.py apply --deployment-state /var/lib/belt-gateway-deploy/review-02 --state-dir /var/lib/belt-gateway-deploy/route-alias-01
```

preview 验证原事务为 `applied`，当前 Caddy 与原事务部署哈希及 inode 一致，SSH 文件、专用账户、公钥均未变化。只在唯一且格式完全匹配的安全带路由区块中增加一个精确别名，保存独立的私有原件和候选，执行 `caddy validate`；原安全帽、网站、SSH 及账户不变。apply 再次核对基线，在原 inode 写入 Caddy 后只 reload 并检查网站。重复 preview 保留原记录；已完成 apply 只有在当前内容和所有受保护资源仍匹配时才返回已完成，不重复 reload。

写入、reload 或最终状态保存失败会尝试恢复补丁前的 Caddy 并 reload。若进程在写入后退出，可通过 `prepared` 记录恢复执行；若出现后续外部改动则停止，不覆盖未知内容。恢复 reload 失败可以重试补丁 rollback。输出只含固定状态，不打印路径凭据或候选内容。补丁不会操作 SSH 配置、隧道进程、账户、公钥、后端或原部署 journal。

```sh
sudo python3 /root/belt-route-alias/route_alias.py rollback --deployment-state /var/lib/belt-gateway-deploy/review-02 --state-dir /var/lib/belt-gateway-deploy/route-alias-01
```

完整撤销安全带部署时，必须先依次撤销后续 `short-ws-01`、`legacy-ws-01`、`default-sni-01` 补丁，再成功运行上述别名 rollback，最后使用原脚本回滚 `review-02`。原事务哈希故意保持不变，跳过后续补丁的 rollback 会被内容保护检查拒绝。

## 缺少 SNI 的 TLS 客户端兼容补丁

限时被动观察出现无 SNI 的 TLS 1.2 ClientHello 和服务端 fatal alert 80，独立探针也复现了带 SNI 成功、无 SNI 失败。`default_sni.py` 已通过独立事务 `/var/lib/belt-gateway-deploy/default-sni-01` 应用，并通过 8 项隔离测试（含旧补丁共 44 项）。`2026-10-21T09:59:32Z` 的应用后对照确认：带 SNI 与无 SNI 的 TLS 1.2 握手均成功，CA 和 `lingzhiaide.com` 域名校验均通过；该补丁应用时的 Caddy SHA-256 为 `6a7a8667e373ba184f91dc8122ed90451b9037d4d48f22f6640c49a902c57b5a`。证据见 [应用前](../../../../../output/device-ready/belt-deploy-20261020/tls-nosni-before.json)和[应用后](../../../../../output/device-ready/belt-deploy-20261020/tls-nosni-after.json)。两次探针均未发送 HTTP 或模拟设备登录，实物登录、定位和状态上报仍待验证。

补丁仅在原配置最前方添加以下固定全局块；[Caddy 官方文档](https://caddyserver.com/docs/caddyfile/options#default-sni)说明此选项为未携带 SNI 的 ClientHello 选择默认 TLS ServerName。

```caddyfile
{
    default_sni lingzhiaide.com
}
```

`default_sni.py` 已放入 `/root/belt-route-alias/`，与冻结版本 `route_alias.py`、`deploy.py` 同目录，旧脚本保持不变。实际 Caddy `2.11.4` 已通过 `caddy validate`；以下命令记录已完成的事务。

```sh
sudo python3 /root/belt-route-alias/default_sni.py preview --deployment-state /var/lib/belt-gateway-deploy/review-02 --alias-state /var/lib/belt-gateway-deploy/route-alias-01 --state-dir /var/lib/belt-gateway-deploy/default-sni-01
sudo python3 /root/belt-route-alias/default_sni.py apply --deployment-state /var/lib/belt-gateway-deploy/review-02 --alias-state /var/lib/belt-gateway-deploy/route-alias-01 --state-dir /var/lib/belt-gateway-deploy/default-sni-01
```

补丁应用前要求别名事务为 `applied`，Caddy 与其 `afterSha256` 及元数据匹配，并重新验证原部署的 SSH、账户、公钥保护链。只前置固定全局块，原 inode、站点及鉴权路由、TLS 协议和密钥配置保留；两个旧事务完全不改。重复 apply 不重复 reload；失败恢复到已含别名的配置。基础网站健康检查使用正常 SNI，本次已另行完成无 SNI 握手、证书链和域名对照；这些基础设施检查仍不能代替实物登录及持续上报验收。

```sh
sudo python3 /root/belt-route-alias/default_sni.py rollback --deployment-state /var/lib/belt-gateway-deploy/review-02 --alias-state /var/lib/belt-gateway-deploy/route-alias-01 --state-dir /var/lib/belt-gateway-deploy/default-sni-01
```

当前已应用事务的回滚顺序为 `short-ws-01` → `legacy-ws-01` → `default-sni-01` → `route-alias-01` → `review-02`。只撤销 TLS 兼容补丁时，在其后续补丁已撤销后运行上面的命令。

## 明文 WebSocket 兼容入口（已部署）

对接方确认设备使用 `ws://` 后，独立 `legacy_ws.py` 已完成云端 preview/apply，事务为 `/var/lib/belt-gateway-deploy/legacy-ws-01`，见[云端应用记录](../../../../../output/device-ready/belt-deploy-20261020/cloud-legacy-ws-applied.png)。本地 12 项新增隔离测试及原有 44 项回归全部通过；部署脚本和旧辅助脚本哈希保持不变。本地 Node 网关于 `2026-10-21T11:02:39Z` 重启（当时 PID `65236`），44 项测试通过，私有 `wsHat` 别名已生效；Java 的 21 项定向测试修复也已上线。本地与公网错误设备 ID 验收通过，见[公网网关证据](../../../../../output/device-ready/belt-deploy-20261020/public-gateway-evidence.json)。

厂家平台仅修改本设备的 HTTP 与长连接两项地址；`2026-10-21T11:09:05.852934Z` 回读与目标一致，见[配置回读](../../../../../output/device-ready/belt-deploy-20261020/vendor-config-read-check.json)和[保存记录](../../../../../output/device-ready/belt-deploy-20261020/vendor-plain-ws-saved.png)。HTTP 为 `http://caps.runde.pro/api/`，WS 完整值已同步到本机 `.local/厂家平台配置.txt`。`11:11:25 UTC` 的真实安全带状态仍为 `NOT_CONNECTED`；`11:11:14–11:12:12 UTC` 的 58 秒云端观察中，80/443 均没有新 TCP。当时尚未收到实物开机确认，这些历史观测不能归因于设备故障；开机确认后的验证见下文。

历史实物验证（2026-10-22 UTC）：用户已明确确认安全带已开机；`00:42:39`、`00:43:47`、`00:44:27` 三次检查仍为 `NOT_CONNECTED`，`lastSeen` 和 `telemetryReportedAt` 均为 `null`，未出现真实设备的首帧通过校验或 `ws_login_forwarded`。`00:43:25–00:43:26` 新增网关事件全部来自错误设备 ID 自检，不是实物登录。`00:43:26` 公网网关验收通过，厂家 `caps` 与文档所列 `mg` 引导接口均读回当前 HTTP/WS 地址，但尚不清楚硬件是否实际获取了这些配置。本轮云端浏览器超时，没有有效入站捕获，不能据此判断设备请求是否到达云端。当时结论为已开机但未接通；下一步需要设备端取配置结果、实际连接目标和失败日志。 证据见[最终实物状态](../../../../../output/device-ready/belt-deploy-20261020/physical-after-confirmed-poweron-20261022-20261022-004427Z.json)、[本轮公网验收](../../../../../output/device-ready/belt-deploy-20261020/after-confirmed-poweron-0046-public-gateway-evidence.json)、[厂家配置回读](../../../../../output/device-ready/belt-deploy-20261020/after-confirmed-poweron-0046-vendor-config-read-check.json)和[引导接口对照](../../../../../output/device-ready/belt-deploy-20261020/after-confirmed-poweron-0046-documented-bootstrap-comparison.json)。

此历史补丁只在已应用 `default-sni-01` 的 Caddyfile 末尾追加以下站点，既有文件字节全部保留。使用已映射的 80 端口，不新增端口映射，不公开私有的 `28087`。当时只增加一个完整凭据的精确路径；2026-10-26 UTC 再由下一节的 `short-ws-01` 事务追加短别名。URI 保持不变，其他路径返回 404，设备号与 WebSocket 首帧仍由网关校验。以下历史地址形状使用占位符，不能直接用于厂家配置；完整地址仅存于本机私有文件。该入口按设备要求使用明文传输，不提供 TLS 的保密性和完整性。

```caddyfile
# BEGIN BELT LEGACY WS
http://39.106.212.138 {
    @belt_legacy_ws path /<私有路径凭据>/wsHat
    handle @belt_legacy_ws {
        reverse_proxy 10.255.1.1:28087
    }
    handle {
        respond 404
    }
}
# END BELT LEGACY WS
```

官方规则见 [HTTP 站点地址](https://caddyserver.com/docs/caddyfile/concepts#addresses)、[精确路径匹配](https://caddyserver.com/docs/caddyfile/matchers#path)和 [handle 后备路由](https://caddyserver.com/docs/caddyfile/directives/handle)。脚本已部署在 `/root/belt-route-alias/`，保留现有 `default_sni.py`、`route_alias.py`、`deploy.py` 原文及哈希；不要覆盖原 `/root/belt-deploy/deploy.py`。以下 preview/apply 命令记录已完成的事务。

```bash
sudo python3 /root/belt-route-alias/legacy_ws.py preview --deployment-state /var/lib/belt-gateway-deploy/review-02 --alias-state /var/lib/belt-gateway-deploy/route-alias-01 --sni-state /var/lib/belt-gateway-deploy/default-sni-01 --state-dir /var/lib/belt-gateway-deploy/legacy-ws-01
# 本次已完成的 apply：
sudo python3 /root/belt-route-alias/legacy_ws.py apply --deployment-state /var/lib/belt-gateway-deploy/review-02 --alias-state /var/lib/belt-gateway-deploy/route-alias-01 --sni-state /var/lib/belt-gateway-deploy/default-sni-01 --state-dir /var/lib/belt-gateway-deploy/legacy-ws-01
```

预检要求 `default-sni-01` 仍为 applied，活动 Caddy 的 SHA、inode、属主和权限与其结果一致，并验证旧别名、原部署、SSH、专用账户及公钥保护链。新事务记录四份脚本哈希和完整旧事务链，不修改旧记录。应用沿用原 inode，经 Caddy validate 后 reload，同时验证既有 HTTPS 网站和新 IP 站点对无凭据无关路径返回 404；这项健康检查不模拟设备登录，也不证明 WebSocket 升级和上游链路可用。本次已另行通过错误设备 ID 的公网 WebSocket 拒绝验证，仍需等待实物自然登录和上报。失败时恢复本补丁之前的配置；后续外部改动会阻止覆盖。

```bash
sudo python3 /root/belt-route-alias/legacy_ws.py rollback --deployment-state /var/lib/belt-gateway-deploy/review-02 --alias-state /var/lib/belt-gateway-deploy/route-alias-01 --sni-state /var/lib/belt-gateway-deploy/default-sni-01 --state-dir /var/lib/belt-gateway-deploy/legacy-ws-01
```

当前完整撤销顺序为 `short-ws-01` → `legacy-ws-01` → `default-sni-01` → `route-alias-01` → `review-02`。只撤销明文入口时先撤销短别名，再撤销 `legacy-ws-01`，既有 HTTPS/WSS 入口保留。

## 短路径 WebSocket 兼容补丁（已部署）

2026-10-26 UTC 本轮早期实物抓包确认厂家配置正文已从 2999 字节减至 916 字节，完整 HTTP 回包约 1405 字节，设备出现 `g_config_parse_ok:1`，配置接收与解析已越过原卡点。但随后的 TCP 连接成功后，固件只发出 199 字节 WebSocket 握手，结尾为 `Upgrade: websock`，缺少 `et\r\n\r\n`。按相同请求头重建，完整请求应为 205 字节。这是配置解析成功后暴露的下一处长度兼容问题，不能继续沿用“配置仍解析失败”的旧结论，也不能把 TCP 成功当成 WebSocket 或业务登录成功。

新脚本 `short_ws.py` 已通过独立事务 `/var/lib/belt-gateway-deploy/short-ws-01` 完成预览和应用。本地网关取原 43 字符凭据的前 24 字符作为短路径，保留 144 bit 随机性；对应完整握手为 186 字节，隔离重放获得 101。云补丁只修改现有 `# BEGIN BELT LEGACY WS` 块内的一行，其余文件字节保持不变：

```caddyfile
    @belt_legacy_ws path /<原43字符凭据>/wsHat /<同一凭据前24字符>/wsHat
```

候选仅增加 32 字节，旧完整凭据 `/wsHat` 继续接收，原 HTTPS/WSS `/wsBelt` 及其他网站、安全帽路由不变。不开放裸 `/wsHat`、短凭据 `/wsBelt` 或短凭据 HTTP 配置接口。网关三条 WS 路径共用同一单设备身份、首帧、速率、连接数与超时校验；没有创建新的公共通用代理。

本轮 49 项网关测试与 75 项云端隔离测试通过，后者包含 12 项短路径事务测试，覆盖字节级最小修改、旧事务保护、候选篡改拒绝、原 inode、校验与 reload 失败回滚、恢复重试、幂等及不输出凭据。本机已重启短路径代码（当次 PID `40908`）。厂家配置修改检查显示仅 `notice.ws_url` 和 `bootstrapConfig.ws_url` 变化；部署和配置回读之后，已继续完成如下独立实物验证。

成功启动抓包 `20261026-024036Z-ttyUSB4-boot.bin` 共 11784880 字节，包含配置正文 897 字节、完整 HTTP 回包 1386 字节，实际 `ws_url` 为匹配短路径的 53 字符地址。设备完整发送 186 字节 GET 握手，收到 HTTP 101；业务日志序号 80290 为 `login server success!!!`，80303 为 `login ok start heart`。网关在 `02:41:20 UTC` 接受真实首帧，`02:41:21 UTC` 完成登录转发；`02:43:15 UTC` 保存的三接口核对均显示在线、遥测 `CURRENT`，最近数据时间 `02:43:08 UTC`，电量 100。未发送模拟设备登录或心跳；本结论仅涵盖真实登录与管理端、PC 前台、安卓端对应后端接口的遥测一致性，SOS、定位质量、佩戴/挂钩动作及长期稳定性仍需分别验收。

`02:45:04 UTC` 的[再次核对](../../../../../output/device-ready/belt-deploy-20261020/three-client-state-20261026-024504Z.json)仍为三个接口全部在线、遥测 `CURRENT`，数据时间由 `02:43:08` 推进到 `02:44:48 UTC`，挂钩 B 状态由 1 变为 0 且三接口一致。由此进一步确认真实遥测持续更新；这一状态变化观察不替代挂钩动作语义、报警逻辑及其他业务功能的专项验收。

只上传新的 `/root/belt-route-alias/short_ws.py`，保留同目录 `legacy_ws.py`、`default_sni.py`、`route_alias.py`、`deploy.py` 及所有旧事务原文。新脚本 SHA-256 为 `1e333d350b5fc65965a4201409e58ae86a08346de7e84c3e1b39dd938d02f07f`。下面是本次已经完成的命令记录：

```sh
sudo python3 /root/belt-route-alias/short_ws.py preview --deployment-state /var/lib/belt-gateway-deploy/review-02 --alias-state /var/lib/belt-gateway-deploy/route-alias-01 --sni-state /var/lib/belt-gateway-deploy/default-sni-01 --legacy-state /var/lib/belt-gateway-deploy/legacy-ws-01 --state-dir /var/lib/belt-gateway-deploy/short-ws-01
sudo python3 /root/belt-route-alias/short_ws.py apply --deployment-state /var/lib/belt-gateway-deploy/review-02 --alias-state /var/lib/belt-gateway-deploy/route-alias-01 --sni-state /var/lib/belt-gateway-deploy/default-sni-01 --legacy-state /var/lib/belt-gateway-deploy/legacy-ws-01 --state-dir /var/lib/belt-gateway-deploy/short-ws-01
```

事务验证 `legacy-ws-01` 仍为 applied、当前 Caddy 哈希与元数据一致，并追溯旧别名、TLS、原部署及 SSH/账户/公钥保护链。预览与应用均执行 `caddy validate`，写入保持 inode，只 reload；失败恢复补丁前配置，拒绝覆盖后续外部修改。应用后检查既有 HTTPS 网站及无凭据 HTTP 请求被拒绝，这些检查不模拟设备登录。

只撤销短别名时使用同一事务，完整凭据路径及旧 HTTPS/WSS 入口保留：

```sh
sudo python3 /root/belt-route-alias/short_ws.py rollback --deployment-state /var/lib/belt-gateway-deploy/review-02 --alias-state /var/lib/belt-gateway-deploy/route-alias-01 --sni-state /var/lib/belt-gateway-deploy/default-sni-01 --legacy-state /var/lib/belt-gateway-deploy/legacy-ws-01 --state-dir /var/lib/belt-gateway-deploy/short-ws-01
```

若设备已改用短地址，撤销此别名前须安排设备恢复到可用接收地址；回滚云配置不会自动修改厂家下发值。本机 fallback 当前也优先返回短路径，需要一并按回滚目标核对。完整云端回滚顺序为 `short-ws-01` → `legacy-ws-01` → `default-sni-01` → `route-alias-01` → `review-02`。

## 回滚

先回滚已应用的 `short-ws-01` 短别名，再回滚 `legacy-ws-01` 明文入口；随后按顺序回滚 `default_sni` 和配置别名。然后停安全带隧道，按厂家可用配置路径恢复安全带原地址，使用保留的原部署脚本运行：

```sh
sudo python3 /root/belt-deploy/deploy.py rollback --state-dir /var/lib/belt-gateway-deploy/review-02
```

只接受带 `belt-device-gateway` 标识、`belt-tunnel` 用户和 `28087` 端口的事务，误传安全帽事务目录立即拒绝。按部署哈希检查后原 inode 恢复，原文件包含的安全帽入口原样保留；只删除本事务确认拥有的安全带用户、组、公钥和空目录，不递归删除目录。重复回滚可重试先前失败的 reload。

如果配置、账号身份或公钥后来变化，停止覆盖并保留私有 state 和归档供核查。它不会还原后端镜像/数据库、删除安全帽资源或更改已有站点防火墙规则。
