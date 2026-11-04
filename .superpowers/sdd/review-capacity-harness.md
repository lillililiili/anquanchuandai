# 容量部署及 reset 独立只读审查

最终结论：初审 3 项 P2 已修复并通过独立只读复审，当前没有剩余 P1/P2。正式 Python stage reset 路径的代码守卫可以进入父协调方授权决策；本审查不授予执行权限，也不证明真实重置或容量测量已成功。资源不足时仍须由既有守卫拒绝。当前没有执行或授权 DROP/reset，也未访问运行中的 Docker、网络或数据库。仅新增/更新本报告，无产品修改、提交或资源调整。

## 初审发现（以下 3 项均已关闭，最终复审见文末）

### P2：共享路径前置条件在 DROP 之后才检查

位置：`output/dm8-cluster/private/capacity-deploy/capacity-stage.py:161-165`。

`schema('drop', ...)` 先执行，随后才检查 shared 的归属、符号链接以及 preserved 目标是否已存在。若 `capacity-store-single5m-preserved` 已存在，或共享路径不合要求，脚本会在旧 schema 已删除后拒绝。备份尚在，不等于可以在明知下一步不能完成时先执行不可逆步骤。

全内存负例抽取真实 reset 函数，替换所有外部依赖；给定归档目标已存在，得到：`fresh-reconcile → reset-journal → schema-drop → SHARED_ARCHIVE_PATH_REJECTED`。未调用真实 schema 或文件操作。

授权条件：把共享根、归档目标不存在、下一轮目标配置与目录等可预先确定的检查移到首次破坏性操作前；测试上述负例必须断言 schema drop 从未调用。保留已有新建 reset-started 日志和失败后不自动重放机制。

### P2：正常断线导致少发报文时仍可能被认定同负载成功

位置：`output/dm8-cluster/capacity-final/capacity-driver.mjs:94-106`、`run-capacity.py:188-198`、`compare-capacity.py:41-46`。

若服务在成功 ACK 后的等待期间正常关闭连接，循环退出并经过 500ms 后重连；重连成功可令 login/reports errors 和 cadenceOverruns 都保持 0，但实际发送量下降。runner 对实际发送的报文逐条对账，却不检查报文发送时间表缺口或连接空档；compare 只比较配置节拍和设备集合，不核对实际负载完整性。因而不同实际报告量仍可能获得 COMPARABLE_MEASUREMENTS，与 README 所述“不把降低发送量当同负载成功”不符。

全内存执行真实 compare：保持配置、资源、baseline、工具摘要一致，两个已标为 MEASURED_AND_RECONCILED 的输入分别为每设备 300 与 200 个无错误且已 ACK 报文，返回 COMPARABLE_MEASUREMENTS。该负例隔离了比较逻辑，未伪称复现真实网络断线。

修复条件：记录并校验每设备发送节拍缺口/连接空档，或在此固定有限负载下明确拒绝非预期重连与降低的发送覆盖；不能仅要求 attempt=ACK=落库。比较端也应保留并校验该完整性证据。

### P2：原验收环境 10 服务冻结没有进入实时守卫

位置：`output/dm8-cluster/private/capacity-deploy/capacity-stage.py:67-71`；三个 `rounds/*/plan.pending.json` 的 mustBeStopped；`capacity-final/run-capacity.py:67-68`。

`final-original-apps-stopped.txt` 包含原验收 10 个服务的停止证据，但 parent_stopped 实际读取的 baseline export-offline-readback.json 只有 2 个 app ID，再加 simulator。三个测量计划也只检查原两 app 和 simulator（single 另加容量 B peers）。所以原 protocol/API/router/ingress 服务若重新运行，实时守卫仍通过；这些额外进程会占用共同宿主资源，违背约定的原 10 服务冻结。这里没有宣称它们当前已经重启。

修复条件：固定原 10 个服务的完整容器 ID，stage/capture/runner 实时验证全部非 Running/Paused/Restarting，保留原历史停止证据。

## 已确认的保护与边界

- `CapacitySchema.java:24-46` 拒绝未知操作，目标 username/schema 和本地 DM 15237 URL 固定；CREATE 仅用户不存在时执行。DROP 是唯一字面量 `DROP USER WEARABLE_CAPACITY_COMPARE CASCADE`，不存在根据任意用户参数生成 DROP；不会选择 LAB1104B 等其他 schema。
- 正式 Python reset 路径核对既有 schema ownership、targetId、密码摘要、DB 容器身份、已封存 manifest/reconcile 摘要及 COMPLETE，再实时执行完整 reconcile，核对 DB7 owner。migrate 校验容器/端点/schema/配置连续性，生成有时限的停机证据；Java transfer 验证实际节点 ID 全被 inventory 覆盖。
- 容量自身全部 10 服务必须停机，另扫描 Docker schema/DB7 使用者并拒绝未清单化 writer。Java 在 DROP 前重新检查 PAUSED、无活租约、ACTIVE 工作、未知/在途媒体、push 及未决控制发送，CAS 持久化 schema lock；产品启动确实会拒绝非空 schema lock owner。
- seal 导出最终 bundle 并 reconcile。fresh pre-reset reconcile 的 Java 实现只有成功验证内容/文件/identity 后才写 COMPLETE；失败会返回非零并中止。因此未显式再次解析其 JSON 不构成此次发现。
- 共享数据采用重命名保留，不递归删除；DB7 先核对专用 owner 再 FLUSHDB。重置不是事务；失败保留 reset-started，重跑因独占新建日志而拒绝。只允许通过受授权的 Python stage 入口运行；直接执行持有管理员配置的 Java helper 不具备 Python 的封存/授权检查，不能作为独立安全入口批准。
- 当前单/双 overlay 分别为 app 2 CPU/1800 MiB/Xmx768/pool12 与各 1 CPU/900 MiB/Xmx384/pool6；协议总量均 2 CPU/1024 MiB；初始/最小连接总量均 2。runner 检查实际 CPU、内存、堆与容器/镜像，compare 检查公共依赖同 ID/镜像/资源。池配置来自受 hash 保护的 overlay，未另行声称已读回实际连接池运行值。
- runner 对测量期 attempt、ACK、tagged raw、processed、全部原始增量逐项相等；帽双定位表增量相等、alarm/SOS 不增、pending 清零、重复读回稳定。业务连续 3 次错误、读回失败/超时、持续积压会中止；任意最终错误使结果无效。两个采样器在采样错误时非零退出，runner 会拒绝；compare 另检查采样错误、跨度和间隔。
- monitor 创建仅含两个 SELECT grant，没有 RESOURCE/DBA 回退；capture 要求实际权限审计证据。私有三轮 metrics 配置均指向专用 WEARABLE_CAPACITY_MONITOR。此次没有自行访问数据库核实账号已创建或实际权限。

## 初审验证证据

只读核验最终 jar 与 release-image-identities.json 的 SHA256 一致：`35290a865fe8169bdaeeacab57151e379b7235a2808a4e7cbf0e8358158e8614`。baseline manifest 为 COMPLETE，applicationSha256 相同，manifest SHA256 为 `09076c923c76db8d5e287bf21f0897be88b344b70a207ec1dbd2121fc4eff99b`。prepared-config-sha256.json 所列文件本次核验无差异。没有读取导出业务行或打印私有凭据。

审查基线源码摘要：

- capacity-stage.py：`b8ccd211d30c6dbba08618118a1fb711cdee2a1654caf154a7fc61d9b0ec8036`
- CapacitySchema.java：`31a058a59409ef4353b1b167712ca85fd640d18a7acee5ebcc7fbbebb9111ca8`
- run-capacity.py：`fca572446a0510c3b0afa080e9dc1c5578554841d6d5b387d2466dc771cfa2a4`
- capacity-driver.mjs：`03411a8059148f2e15979d385884ce596dbbc77c1f7351be05fac2f43b90e68e`
- compare-capacity.py：`9c53b6ef2a082f6205b974a83e8ccd2fc15c2c556b7f64f72d2f5adb7d048296`

既有 preparation 测试源码已阅读；未运行会生成 fixture 目录的整套测试，仅运行上述两项 AST 抽取、全部依赖内存替换的负例。不把静态审查或离线负例等同于真实 reset/测量验收。

## 最终独立复审

1. 第 1 项关闭。`capacity-stage.py:162-185` 新增 reset_paths，并作为 reset 第一项调用。检查共享真实目录及整个父路径不含 symlink/junction、精确同根路径、归档不存在、固定轮次、下一轮 schema/username/URL/DM containerId/密码连续性/共享路径/不同 UUID targetId、目标目录和各输出 journal 未使用、上一轮 reset 不可重放。实际 DROP 位于这些检查之后。独立 AST 全内存负例：归档已存在、下一轮错误 schema、错误 DBID、restore journal 已存在、reset journal 已存在，全部拒绝且 schema 调用次数均为 0。
2. 第 2 项关闭。driver 用跨重连不重置的绝对 due，记录 reportScheduleSkipped 和 unexpectedDisconnects。新增纯函数 `capacity_contract.py`，由 runner 对 warmup/measure 分别调用，独立 compare 也调用；要求每设备发送/ACK 恰为秒数、总报告和 GET 均为秒数 × 4，login 为 4，任何重连、意外断线、漏槽或错误均拒绝。合同文件加入 toolHashes，900 秒后续比较不能忽略它的变化。初审 300 对 200 负例现在明确拒绝。
3. 第 3 项关闭。parent_stopped 依据父最终 10 服务停止证明验证完整名称、project、非活跃状态，并持久固定全部当前 containerId；原 app 另核验 final image、LAB1104B/Redis6 与配置连续性。capture-plan 合并 10 个原服务到 mustBeStopped，并写 mustBeStoppedIdentities；runner validate_plan 要求 10 名齐全、每个 ID 为完整 64 位，inspect_resources 在前后读回检查相同 ID 且均非 Running/Paused/Restarting。

独立执行前已检查测试无真实网络/数据库调用。实际运行 `python -B -m unittest -v test_capacity_contract.py`：7/7 通过；`node --test driver-cutoff.test.mjs`：4/4 通过，测试使用 VM 注入假 WebSocket/fetch，保留真实事件调度。覆盖少发、GET 不足、重连、ACK 后空闲断线、漏槽、单独 comparator 拒绝 300 对 200、收尾 ACK 与超时边界。另 5 项 reset 负例全部在内存执行，无文件或服务修改。

协调方 `capacity-final/review-fixes-verification.json` 记录 preparation 22、contract 7、business guards 10、driver 4 全通过；其中 preparation 22 和 business guards 10 不是本审查自行重复运行的结果，不混同证据。最终再次只读核验 64 个 prepared config 文件，0 个 hash 不匹配。

最终复审源码摘要：

- capacity-stage.py：`76400647e10c2daf6eba931d993633a234af0ec2841af918cb2a9921002e7b61`
- capture-plan.py：`2944257fd43391a720883f840faeb87cccffd075be4347515151c83b5852eadb`
- capacity_contract.py：`1045cc7141fdcca85cc4700916c575757ff4a1f05b6177276ebee6a0318610b2`
- run-capacity.py：`1fc32a048670e418cb0300a904e5692f5aa5a0b6f03a05222cde8ec2bd6c4f27`
- capacity-driver.mjs：`be8835a72b21d98cf42693e353062207076b73349dd8444fbcd31f9b71f0df17`
- compare-capacity.py：`ee03bcf09fe20ceb7486e129de870f7e589836e085f78b350b8be6a5825dd4f3`

验收界限：可以判断上述可执行守卫和离线拒绝路径成立；不能把它改写为“容量已达标”“DM 当前有资源”或“DROP 已获授权”。本次仍没有真实 reset、负载、监控权限 SQL 或容器运行状态验收。
