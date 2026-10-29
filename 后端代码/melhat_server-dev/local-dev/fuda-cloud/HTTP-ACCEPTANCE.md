# 服务器 HTTP 验收器

`verify_staging_http.py` 只调用三个只读 POST 查询接口。它不改数据库、不启动服务、不控制设备。实际接口会按设计登记鉴权 Nonce。

仅需 Python 3.6 或更新版本的标准库，不需要安装额外依赖。

仅允许字面回环 IP 和显式端口，默认 `http://127.0.0.1:18089`，禁止日常后端及设备端口 18084/18086/18087/18088；不使用环境代理、不跟随重定向。可在服务器直接运行，也可通过另行建立的专用 SSH 本地转发使用其他回环端口。

## 私密输入

创建仅部署账号可读的 JSON 文件，内容为本次独立测试应用的 `appId` 和 `secretBase64`，Linux 权限 0600。它必须匹配服务端已启用的应用；不要使用协议中的公开测试向量密钥。

也可从进程环境或 `--env-file` 读取 `FUDA_VERIFY_APP_ID`、`FUDA_VERIFY_SECRET_BASE64`。脚本不会执行 env 文件中的任何命令。不要把密钥作为命令行参数或打印到终端。

默认设备为本次批准的安全帽、安全带接入号。如有变化，用 `--devices-json` 传入私密 JSON 数组，每条含 `deviceType`、`deviceId`。

## 初次运行及重启验证

先确认独立 staging 已完整启动并恢复快照。下面的凭据文件应由部署过程私密生成：

```sh
python3 verify_staging_http.py \
  --credentials-json .private/staging/http-credentials.json \
  --page-size 2 \
  --checkpoint-out .private/staging/http-before-restart.json \
  --report-out reports/http-first.json
```

默认要求设备为 OFFLINE，因为 staging 未接真实设备；旧测量不能标为当前有效。默认还要求至少一条已保存报警，避免把空页测试当作历史同步、去重验收。只有明确做空库启动检查时才传 `--min-historical-alarms 0`；报告会保留 `nonemptyAlarmRepeatExercised=false`。

由部署负责人真正重启本次隔离服务后，再执行：

```sh
python3 verify_staging_http.py \
  --credentials-json .private/staging/http-credentials.json \
  --page-size 2 \
  --checkpoint-in .private/staging/http-before-restart.json \
  --checkpoint-out .private/staging/http-after-restart.json \
  --report-out reports/http-after-restart.json
```

若已通过独立、明确授权的隔离数据写入路径产生新的测试报警，可在第二次运行增加 `--min-new-alarms 1`，验证旧游标续拉所得新报警与全量结果一致。验收器本身不会制造报警。仅重复执行脚本，不能称为已经验证服务重启或新增写入。

## 检查及报告

包括合法签名、LF/CRLF 原始正文、错签名、时间超窗、真实 Nonce 重放拒绝、整批越权拒绝、无效游标、重复 JSON 键、字段空值/离线规则、历史分页、重复拉取和游标追平。带 checkpoint 时还验证先前报警不可变、旧游标续拉结果与当前全量新报警集合一致。

输出只有检查名称、结果、数量和摘要，不打印设备号、报警正文、密钥或游标。checkpoint 包含签名游标及事件摘要，仅写入新建 0600 文件，不覆盖已有证据。任一失败退出码为 2；全部通过退出码为 0。默认最多扫描 100 页，超出范围明确失败而不假称历史完整。

这些检查仍不证明真实设备入口、生产 HTTPS/Caddy 路由、MySQL 并发写入完整性、媒体 RTP/音视频互通或关开发电脑后的生产连续运行。上述验收需单独执行并记录。

## 离线测试

```sh
python3 -B -m unittest test_verify_staging_http.py
```

离线测试不打开网络连接；覆盖签名向量、loopback 限制、分页及去重、空历史拒绝、恢复不变量、输出脱敏和证据不覆盖。
