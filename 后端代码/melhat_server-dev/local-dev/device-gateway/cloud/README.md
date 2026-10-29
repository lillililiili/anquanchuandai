# 独立设备入口：云端预览与应用

当前状态：已在用户指定的北京服务器完成 `review-01` 预检与应用，并验证真实安全帽经 4G 上线、三端状态一致及转发断线自动恢复。现有知识库首页正常。下列部署步骤保留用于核查与回滚，不要对已完成的事务重复 apply。运行记录在 `.local/helmet-tunnel-process.json`，最终实机证据在 `.local/three-end-4g-evidence-final.json`。

目标固定为 `39.106.212.138`、现有域名 `lingzhiaide.com`、容器 `knowledge-base-gateway-1`。本目录脚本不会启动隧道、重启容器、修改防火墙、修改现有账号公钥或本机 backend。创建公网设备入口前，先完成服务器 preview 并取得用户对具体改动的确认，再执行 apply。

`deploy.py` 使用 Python 3.6 标准库，服务器上需要 root、Docker、systemd、OpenSSH、useradd/userdel/pkill。新系统账号默认锁定密码，因此预检要求已有 `UsePAM yes`；旧 OpenSSH 不支持限制指令时在 `sshd -t` 阶段停止，不能删减限制绕过。

## 本地隔离测试和私有输入

在本目录执行：

```powershell
python -m unittest -v test_deploy.py
python prepare_local.py
```

第二条只从已有 `.local/config.json` 读取路径凭据、从 `.local/helmet_tunnel_ed25519.pub` 读取公钥，生成被忽略的 `.local/cloud-settings.json`。不会读取、复制或输出 SSH 私钥，也不会修改网关配置或设备 URL。不要把该 JSON、带秘密路径的候选文件或诊断日志贴到聊天/版本库。

通过已授权的 Workbench 文件上传，将 `deploy.py` 和私有 settings 放入云端 root 专用目录，权限目录700、文件600。私钥始终留在 Windows。服务器预览不需要 settings，使用无效占位路径。

## 服务器 preview（不改活动配置/账号）

每次使用新 state 目录；下列目录名是示例。

```sh
sudo python3 /root/helmet-deploy/deploy.py preview --state-dir /var/lib/helmet-gateway-deploy/review-01
```

预览检查：现有网站本机 HTTPS 证书和 HTTP 响应、Caddy 单文件挂载、SSH 服务、桥网地址/端口、专用账号/组/目录不存在。生成候选 Caddyfile 和 sshd_config，实际执行 Caddy validate、sshd -t/-T；对比 admin/root 的有效 SSH 配置。候选配置、原文件副本和哈希仅保存在私有 state 目录。Caddy 验证采用容器内 `/dev/stdin` 并继承其 `DOMAIN` 环境；诊断全部保存私有文件，终端不回显秘密路径。

## 用户确认后的 apply

```sh
sudo python3 /root/helmet-deploy/deploy.py apply --state-dir /var/lib/helmet-gateway-deploy/review-01 --settings /root/helmet-deploy/cloud-settings.json
```

必须使用同一份脚本与通过预览的 state。apply 再核对原配置哈希、inode、权限和属主、服务状态及端口空闲；归档备份后创建 `helmet-tunnel`。账号只允许公钥验证和 `10.255.1.1:28086` 远程 TCP 转发，禁 shell/SFTP/Unix socket/TUN；密钥仅赋予需要的转发能力。

Caddy 仅把主域秘密路径下的两个精确入口 `/api/index.php` 与 `/wsHat` 转发到 `10.255.1.1:28086`，不剥离 URI；其余主域请求继续 nginx，后续 www 块逐字保留。两份活动配置都在原 inode 写入；SSH 与 Caddy 仅 reload。失败时按部署哈希恢复原配置、reload、终止本次专用 UID 的进程并删除本次账号/组。若检测到其他操作者后续改动，则保留并明确报告需人工处理，不覆盖。

桥网端口可被宿主机/同桥网容器访问，不等于仅 Caddy 可达。`PermitListen` 限制云监听点，无法限制持有私钥的客户端选择的右端目标；保护专用私钥，不开放28086公网规则。

## 随后启动本地网关与 SSH（本脚本不会执行）

在网关目录确认私有配置的 `publicOrigin` 为 `https://lingzhiaide.com`，保留原 token。先 `npm.cmd run check:config`；网关已运行时复用该进程，不重复启动。SSH 主机公钥已从可信 Workbench 核对并存入 `.local/known_hosts`，继续启用严格主机验证。

```powershell
& 'C:/Windows/System32/OpenSSH/ssh.exe' -N -T -a -x -i '.local/helmet_tunnel_ed25519' -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=.local/known_hosts -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -R '10.255.1.1:28086:127.0.0.1:18086' helmet-tunnel@39.106.212.138
```

这是一条前台转发命令，不会自动重连。真实设备 URL 由私有配置组合并直接写帽子，不输出到聊天。后续先验证错误路径/错误设备拒绝、真实 bootstrap，再由实物产生 ca_login/ca_report_location 验收；不要向日常 backend 注入模拟登录。

也可按需使用本地隐藏进程脚本（从网关目录运行）：

```powershell
.\cloud\tunnel.ps1 -Action Start
.\cloud\tunnel.ps1 -Action Status
.\cloud\tunnel.ps1 -Action Stop
```

脚本复用已运行的 `127.0.0.1:18086` 网关，不启动网关或 backend。SSH 使用既定私钥和 `.local/known_hosts`，固定连接22端口及桥网转发地址；后台断线后每10秒重试，连续12次不足60秒便退出则以 `retry-limit-reached` 停止。同一个SSH进程存活满60秒后恢复失败预算，累计 `totalAttempts`（兼容字段 `attempts`）不会清零；`consecutiveFailures` 单独显示连续短失败数。`ssh-running` 和60秒稳定期只表示SSH进程存活，不替代实机心跳验收。状态还保存退出码、短UTC时间和小枚举分类；分类仅读取既有SSH错误日志末尾，不复制日志内容。PID和创建时刻记录在 `.local/helmet-tunnel-process.json`；Stop会核对进程完整命令行、创建时刻、路径及父子关系，只停止本脚本实例。发现已有人工SSH转发时，Start会拒绝重复启动，先由原操作者结束原会话。它不安装定时任务、系统服务或开机自启；电脑及网关需要持续运行、保持联网且不休眠。最近一次SSH诊断在 `.local/helmet-tunnel-ssh.err.log`。

隔离重连状态机测试：从网关目录运行 `pwsh -NoProfile -File .\cloud\test_tunnel_retry.ps1`；只加载决策函数并使用临时日志，不启动SSH、网关或任何网络连接。脚本更新不会改变已运行worker，须由操作人员受控Stop/Start后生效。

## 2026-10-21 安全帽隧道保活

定位诊断期间发现旧 SSH 会话在本地连接消失后仍占用28086。核对专用 UID、PID、父进程和监听端口后仅清理该会话，现已恢复实机上报。用户明确允许仅对 `Match User helmet-tunnel` 增加 `ClientAliveInterval 30`、`ClientAliveCountMax 3`。已完成 `sshd -t`、有效配置校验及管理账号配置不变检查，仅 reload；随后受控重建本地隧道使新设置生效。

变更前备份位于 `/var/lib/helmet-gateway-deploy/review-01/sshd_config.before-keepalive`。原部署脚本及哈希保持不变，因此其旧部署摘要不包含这次保活变更；后续回退应核对并保留其他托管段，不能直接用旧整文件覆盖并行安全带配置。

## 回滚

停止本地 SSH 和网关进程，恢复帽子之前的 USB 引导地址，再运行：

```sh
sudo python3 /root/helmet-deploy/deploy.py rollback --state-dir /var/lib/helmet-gateway-deploy/review-01
```

回滚保留 state/归档供核查，原 inode 恢复活动配置，仅 reload。不会还原 backend 镜像/数据库，也不会触碰既有2222规则。若回滚报告后来配置或账号被改过，先根据私有原件和托管段人工核对，不盲目覆盖。
