# 主动推送开发交付记录 — 2026-11-02

## 结论与代码位置

已完成默认关闭的发送端、协议、模拟接收端和隔离验证，等待福大接收地址及专用凭据后开展双方联调。保留原三个查询接口，不改视频、PC 或安卓功能。

- 开发基线：`3b95131`。
- 开发分支：`codex/fuda-push-20261102`。
- 工作树：`D:\分体式安全帽代码\.worktrees\fuda-push-20261102`。
- 本记录完成时，改动尚未暂存、提交或合并；没有替换运行 JAR 或部署候选服务。后续合并状态及复验见 [main 合并记录](MAIN-MERGE.md)。
- 原目录仍只有开工时已存在的 6 项前端修改/未跟踪目录，后端没有本轮写入。

## 验证证据

| 检查 | 结果与范围 |
| --- | --- |
| 既有福大基线 | 56 项通过（改动前） |
| 后端最终全套测试及打包 | **547 项通过，0 失败，0 错误，0 跳过**；Maven reactor BUILD SUCCESS |
| 新增推送测试 | 63 项，包含在 547 项中：采集 10、队列 5、发送调度端到端 4、HTTP 41、MySQL 3 |
| 真实 MySQL 8.0.46 | 新建一次性隔离容器，验证同设备并发租约、事务回滚/序号间隙、迁移幂等和重构后恢复；3 项通过 |
| Node 原查询网关 | 4 项通过 |
| Node 原国标适配仿真 | 15 项通过；不代表真实国标联调 |
| Node 模拟接收端 | 3 项通过：nonce 防重放、eventId 去重、响应丢失后重试、正文篡改拒绝 |
| 协议 | openapi-spec-validator 校验 OpenAPI 3.1；jsonschema 校验 3 类事件示例；签名向量重新计算一致 |
| 差异 | `git diff --check` 通过；两个增量 SQL 副本摘要一致；代码复核无遗留阻断项 |

覆盖真实回环 HTTP：200 且整数 code=0 才成功，302 不跟随，503 不发生 HTTP 客户端隐式重试，超时/响应体过大/深层 JSON 均受限；先保存但丢失响应后，同一事件使用新 nonce 补发且接收端只保存一份。慢接收端下第二个设备报文继续提交。

事务证据：业务失败/外层事务回滚时 outbox 与内部处理标记一同回滚；提交之前其他连接看不到队列任务。过期租约可恢复，旧 worker 不能覆盖新租约。发送前撤权会取消任务且不发送网络请求。

审查发现并修复了“历史安全带报文恢复时伪造当前上线”的问题。回归先复现 `expected 1 but was 2`，修正后完整回归通过；仅抑制恢复报文造成的 online=true 派生事件，保留真实 OFFLINE 和其他设备 ONLINE。REPORT 始终保留原观测时间。

本机 JDK17 的 HttpServer 测试在含中文的临时套接字目录出现初始化错误；测试 JVM 使用独立 ASCII 目录参数解决，不改应用运行行为。

最终命令（在后端根目录）：

```powershell
$env:JAVA_HOME='D:\DevTools\jdk-17.0.20.1+1'
& 'D:\DevTools\apache-maven-3.9.16\bin\mvn.cmd' -B -pl ruoyi-admin -am '-Dfuda.push.mysqlTestPort=57180' '-DargLine=-Djdk.net.unixdomain.tmpdir=D:/DevTools/fuda-test-tmp' package
```

其中 `57180` 是本次一次性 MySQL 容器的回环随机端口，现已清理，不是可复用服务地址。常规回归省略 `fuda.push.mysqlTestPort`，3 项 MySQL 专用用例将跳过；要复现实际 MySQL 检查，重新创建仅含合成数据的 `fuda_push_test` 库并传入其回环端口，不连接日常库。

测试期间只新增并清理了本轮标记的 MySQL 容器与测试网络。最终只读核对原有 8 个运行容器名称、镜像及运行状态与检查前一致，包括原业务镜像 `melhat-backend:login-20261101`；没有操作原 MySQL/Redis/设备服务。

候选包：`ruoyi-admin/target/fdc-admin.jar`。SHA-256：`9d3184fee7f704baef2cad3ba2a7c9c740511fd816ad074f8d11c8ba72874bc5`。

## 代码变更说明

以下路径相对于后端根目录。文件均限定于本次发送端和验证配套。

| 文件/类 | 方法/函数 | 方法作用及本次代码作用 |
| --- | --- | --- |
| `ruoyi-admin/src/main/java/com/ruoyi/guardian/WearableBusinessStore.java` | `setFudaPushCapture/replace/processReport` | 业务快照、报警、内部报文成功处理时，在原事务中调用推送采集；恢复上下文不伪造当前上线 |
| `ruoyi-admin/src/main/java/com/ruoyi/fuda/FudaPushCapture.java` | `receipt/saved/duringReceipt/authorized/maySend/emit` | 保存原观测时刻的公开字段，复用查询映射及报警判定；按真实设备白名单采集和发送前复核 |
| `ruoyi-admin/src/main/java/com/ruoyi/fuda/FudaPushOutbox.java` | `enqueue/claim/finish/onCommit` | 同事务入队、提交后唤醒、每设备顺序领取、租约恢复、条件确认发送结果 |
| `ruoyi-admin/src/main/java/com/ruoyi/fuda/FudaPushDispatcher.java` | `wakeup/drain/reconcilePresence/close` | 独立线程发送和退避重试；无需打开网页也能核对离线状态；停止时中断工作线程 |
| `ruoyi-admin/src/main/java/com/ruoyi/fuda/FudaPushHttpSender.java` | `send/acknowledgement/readBounded/retryAfterMillis` | HMAC 原始字节签名、严格确认、超时/响应限制及受控 Retry-After |
| `ruoyi-admin/src/main/java/com/ruoyi/fuda/FudaPushProperties.java` | `validate/endpointFor` 及配置访问器 | 默认关闭；独立凭据和白名单；单地址或按类型地址；HTTPS、租约、参数长度校验 |
| `ruoyi-admin/pom.xml` | 无具体方法 | 引入父 POM 已管理的 OkHttp 4.9.1，不升级原依赖版本 |
| `ruoyi-admin/src/main/resources/db/20261102_fuda_push_outbox.sql`、`sql/migrations/20261102_fuda_push_outbox.sql` | 无具体方法 | 同一新增表/索引迁移的运行时与运维副本；不删除或改写原业务表 |
| `ruoyi-admin/src/test/java/com/ruoyi/fuda/FudaPushCaptureTest.java` | 10 个行为测试 | 验证原时间、未知值、设备范围、事务回滚及报警/上下线语义 |
| `ruoyi-admin/src/test/java/com/ruoyi/fuda/FudaPushOutboxTest.java` | 5 个行为测试 | 并发、可见性、幂等、同设备顺序和崩溃恢复 |
| `ruoyi-admin/src/test/java/com/ruoyi/fuda/FudaPushDispatcherTest.java` | 4 个回环 HTTP 集成测试 | 响应丢失、撤权、慢接收端、关闭再启用 |
| `ruoyi-admin/src/test/java/com/ruoyi/fuda/FudaPushHttpSenderTest.java` | 41 个 HTTP/配置用例 | 签名、确认格式、恶意/异常响应、隐式重试和配置边界 |
| `ruoyi-admin/src/test/java/com/ruoyi/fuda/FudaPushMySqlTest.java` | 3 个专用 MySQL 测试 | 实际 MySQL 的事务、租约及迁移行为 |
| `local-dev/fuda-push/mock-receiver.mjs`、`mock-receiver.test.mjs` | `createReceiver`、3 个测试 | 仅回环合成数据接收演示：签名、nonce 和事件 ID 去重；非正式服务 |
| `local-dev/fuda-push/build_contract.py` | `include/write`、协议生成流程 | 从原 V2 数据字段生成推送 OpenAPI、三类示例及公开签名测试向量 |
| `local-dev/fuda-push.example.yml`、`fuda-push/inspect.sql`、`fuda-push/openapi.json`、`fuda-push/examples/*.json` | 无具体方法 | 关闭状态配置、只读积压巡检、可审查协议和虚构样例 |

## 尚未验收

未使用福大真实接收端、真实推送凭据或正式网络；未触发真实设备报警、未做实机端到端推送、未做国标媒体互通、未迁移服务上云。正式启用仍需确认对方接收规范、范围和网络参数，并按 README 的隔离联调/发布步骤操作。
