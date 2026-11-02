# 推送接口 main 合并与复验记录

2026-11-02，已将主动推送接口合并到当前项目的本地 `main`，保留用户原有修改，并在合并后的目录完成测试和打包。未部署、未启用推送、未推送远程。

## 合并范围

- 项目：`D:\分体式安全帽代码\分体式安全帽代码\anquanchuandai`。
- 来源分支：`codex/fuda-push-20261102`。
- 功能提交：`5723c227f60e4e09f856556061f404c8b500dd48`（`feat(fuda): add durable wearable data push`）。
- `main` 从 `3b95131b28f93989ac12328209c4a1c4cf42fa69` 快进到功能提交，无冲突。随后单独提交本记录。
- 功能提交涉及 27 个文件，仅包含推送发送端、业务采集入口、增量 SQL、依赖声明、协议、示例、测试和文档。

新增位置、状态和报警推送，复用现有公开数据字段；同事务保存事件，异步 HMAC 签名发送，按设备顺序重试，发送前复核授权。HTTP 200 且响应中整数 `code=0` 才确认成功。原查询接口继续保留。

代码变更的文件/类、方法/函数及其作用，见 [开发记录中的完整代码变更说明](VALIDATION.md#代码变更说明)。接收协议与可配置项见 [接口说明](README.md)。

## 用户修改保留

合并前备份了 12 个已修改或未跟踪文件，共 19,405,808 字节。合并与构建后逐文件核对 SHA-256，全部一致；原有已跟踪文件的二进制差异与暂存区状态也一致。

Git 状态中的 6 项原有修改/未跟踪路径仍保留：

- `智能穿戴平台-原生还原版/css/theme-tokens.css`
- `智能穿戴平台-原生还原版/css/theme.css`
- `智能穿戴平台-原生还原版/index.html`
- `智能穿戴平台-原生还原版/assets/fonts/`
- `智能穿戴平台-原生还原版/css/fonts.css`
- `智能穿戴平台-原生还原版/scripts/build-sketch-fonts.py`

这些文件没有被暂存或提交。本次没有使用 stash，也没有覆盖用户修改。

备份与证据目录：`D:\分体式安全帽代码\output\fuda-push-main-merge-20261102T061201Z`。其中 `user-changes/` 为原文件副本，`user-changes.json` 为摘要清单，`user-changes.patch` 和 `index-before.patch` 为合并前差异。

## 合并后验证

所有下列复验均在当前项目 `main` 的后端目录执行，而非开发工作树。

| 验证 | 实际结果 | 证据文件（位于上述证据目录） |
| --- | --- | --- |
| 后端全套测试与 Maven package | 547 项通过，0 失败、0 错误、0 跳过；全部 reactor 模块 BUILD SUCCESS | `main-backend-build.log`、`main-verification.json` |
| 新增推送用例（包含在 547 项内） | 63 项：采集 10、队列 5、调度 4、HTTP 41、MySQL 3 | `main-verification.json` |
| 查询网关 Node 测试 | 4 项通过 | `query-gateway.log` |
| 原国标适配 Node 仿真 | 15 项通过；不代表真实国标设备联调 | `gb-bridge.log` |
| 推送模拟接收端 Node 测试 | 3 项通过 | `mock-receiver.log` |
| 协议与签名 | OpenAPI 3.1 校验、POSITION/STATUS/ALARM 示例校验及 HMAC 测试向量重算均通过 | `contract-validation.log` |
| SQL 副本 | 运行时资源与运维迁移脚本字节一致 | `main-verification.json` |
| 用户改动 | 12 个文件摘要、原有已跟踪差异和暂存区一致 | `main-verification.json` |
| 原有运行环境 | 8 个容器的名称、ID、镜像 ID、启动时间、重启次数完全一致 | `runtime-before.txt`、`runtime-after.txt` |

后端命令：

```powershell
$env:JAVA_HOME='D:\DevTools\jdk-17.0.20.1+1'
& 'D:\DevTools\apache-maven-3.9.16\bin\mvn.cmd' -B -pl ruoyi-admin -am '-Dfuda.push.mysqlTestPort=53220' '-DargLine=-Djdk.net.unixdomain.tmpdir=D:/DevTools/fuda-test-tmp' package
```

本次 MySQL 8.0.46 验证使用一次性容器 `fuda-push-main-merge-mysql-20261102`，仅绑定回环地址，使用独立合成数据库；端口 `53220` 是本次随机端口。测试结束已核对所属标签与容器 ID 后清理该容器，没有操作日常数据库。复现时应新建隔离测试库并替换端口。

本次构建产物：`ruoyi-admin/target/fdc-admin.jar`，SHA-256：`6658a2e3abbffdf3456b2be05cba22b58f26ad26b25f9e2517dcf59869b5b945`。仅在本地生成，没有替换运行中的服务。

## 当前边界

`FudaPushProperties.enabled` 默认值为 `false`，示例配置同样为 `enabled: false`；没有填入正式接收地址或推送凭据，没有更改运行配置。原业务容器未重建或重启。

本次验证覆盖合成事件、回环 HTTP 与隔离 MySQL。福大尚未提供正式接收规范，HMAC 和成功响应规则仍是已获用户同意的暂定方案；真实设备及福大接收端的端到端联调尚未进行。部署、正式启用和远程 Git 推送均未执行。
