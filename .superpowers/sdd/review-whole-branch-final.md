# 全分支跨组件最终审查

结论：**Spec Approved / Quality Approved；已知未关闭 P1/P2 为 0。** 最终审核提交 `984fab2786afb1d4f4a44f88cfaea57c5baf9563`（前序全分支及依赖语义审核至 8d79d55，本次 ops 窄复审见末节），基线 `2b6787aafaf87c5c17ba16e550ebc726d38ce2c6`。两项 P2 均已修复复审关闭，细节见末节；前文保留发现与逐次复核历史。最终运行制品、真实故障验收及外部门槛仍独立待验证，本决定不等于系统交付全部完成。

本轮只读检查计划、最终分项报告与实际实现；未运行 Maven、构建、服务、浏览器或数据库，不读取 private 凭据。唯一新增文件为本报告。范围是全分支跨组件风险抽查，不声称 262 个变更文件逐行穷尽审计；不重复将静态报告引用写成亲自执行测试。

## P2：明确未进入 Sender 的拒绝也永久记 UNKNOWN，阻塞正常维护排空

位置：`后端代码/melhat_server-dev/ruoyi-admin/src/main/java/com/ruoyi/cluster/DeviceCommandRouter.java:234-253`，重点 252–253。

具体交错：

1. `dispatch()` 已在 SQL 事务中将命令从 QUEUED 写为 DISPATCHING，并提交原 claim_token（228 行）。
2. 在随后第二次 `guard.dispatch(id)`（236 行）或外层 `fence.run()`（248 行）之前，运维开启全局 PAUSE，或本节点 `beginDrain()`。
3. `ClusterMaintenanceGuard.dispatch()` 第 15 行调用 `identity.requireAdmission()` / `work.requireActiveMode()`，明确拒绝；尚未调用 249 行 `sender.send()`，物理发送数为 0。
4. 统一 catch 将这类已知未发送异常也写为 UNKNOWN。随后 `ClusterWorkCoordinator.status()` 第 129–132 行永久将它计入 uncertainTransport/quiescent=false；`recoverAbandoned()` 第 115 行据此拒绝恢复，而当前维护 reconcile 只向媒体 `/operations` 核对，无 transport 确定未发的解除路径。设备没有收到命令，自然不会有可信 ACK 来解除它。`ops.py` drain/stop/restart 因而持续超时，普通维护操作变为需人工数据修复。

这是活执行者能够证明 sender 未被调用的场景，区别于已经进入 Sender、网络超时以及 claim 后进程死亡的不确定发送。原路由测试中的 before-send kill 保持 UNKNOWN 是正确的，不能作为将此活执行者拒绝也写 UNKNOWN 的依据。已批准媒体 journal R3 的 NOT_SENT 修复和 Fuda releaseUnsent 修复解决了相同分类问题，但 transport 路径尚未同步。

修正方向：为 sender 调用前的异常保留确定未发送证据，以原 command_id+claim_token 条件收敛到既有 FAILED_BEFORE_SEND/CANCELLED 等终态；进入 Sender 后仍保守 UNKNOWN，绝不能以超时或进程死亡推断未发送。需要同时考虑原 claim 已到期但执行者明确未调用的收尾，不覆盖换 claim/已确认的状态。无需自动重发。

建议最小确定性回归：注入 ClusterCommandGuard 在 claim 后第二次 dispatch 检查触发 PAUSE（另测 node drain），断言发送次数 0、同命令重放不新发、命令处于确定未发送终态、排空恢复为 true；保留真实 sender 异常及进程 kill 的 UNKNOWN/no retry 回归。此处仅源码证明和测试设计，未运行该新增测试。

## Spec 其余抽查结论

- 计划明确 DM8 + 保留 MySQL，迁移后 validate-only 启动。DatabaseConfiguration、SchemaLifecycle 的产品/strict runtime/schema checksum/未完成 owner 门禁连接一致，未以应用启动静默 DDL 替代显式迁移。
- owner/generation/connection token、DB 时间租约、raw receipt 与 owner 更新事务、全局 presence，以及 durable command 的不盲重试主路径保留。设备协议没有 epoch 的最后 fencing 到物理 write 窗口是已披露外部边界，不能称端到端 exactly-once。
- 全局维护、work lease/permit、共享 Redis session 与 credentialVersion、六类 ledger writer 的最终分项报告与代码连接已核对；上述 transport 例外阻止本轮整体批准。
- 文件使用不可变随机文件名、flush+atomic move 后数据库 pointer，create-only 在同一数据库锁中判重；共享根 marker 进入写入、读取与 readiness。实际 NFS/断挂语义仍须实机验证。
- 完整 Caddy 入口与私有 backend router 保留零代理重试，HTTP/WS 归组、readiness、内部路径拒绝与 PC 精确例外一致；两套 guardian 入口共享 wear gateway。media 仍为独立服务，没有偷偷承诺媒体多机迁移或 K8s。
- PC/Android 显式区分 queued/dispatching/sent/acknowledged/unknown 与执行完成；事件表单版本修复已有独立审核，本轮未发现客户端新增假成功路径。
- 离线迁移工具对 owner/journal exclusion、归档表策略、内容/文件摘要、identity watermark 的实现定位与既有最终报告一致。已有 71ab732e 的真实双向和 kill 矩阵不能冒充最终 1f0b9939 已重跑。

## Quality 其余抽查结论

未发现其他具备具体触发路径的新增 P1/P2。没有以主观代码风格、未上真实麒麟或尚未执行的父任务验收项目制造第二个缺陷。锁顺序、无数据库事务内网络副作用、未知状态不自动重放、部署配置 generation/旧挂载核验均保留已有安全约束。

已读取 `review-cluster-routing-approved.md`、`review-cluster-coordination-{spec,code}-final.md`、`review-cluster-deployment-approved.md`、`review-migration-recheck.md`、`review-complete-entry.md`、`review-event-form-version.md` 等；旧报告批准只适用原限定范围。本轮未修改原 pubspec.lock、MigrationInspect fixture 或其他未提交工作。

## 验收边界

本报告不要求把尚未提供的真实麒麟 V10 x86_64、实际 NAS/NFS、物理帽/带、真实媒体及长时现场稳定性写成通过。这些仍为外部验收门槛。父任务正在进行的完整应用/UI/Android/容量与最终 artifact migration rebind 也按各自实际证据单独结项；目前读取的容量报告仍为 prepared-only、Android 报告仅到登录前准备，不能据本代码审查扩写完成。

修复上述 P2 后可作窄范围复审；无需无依据地重做已经批准且未受影响的所有分项。

## 77886d7 窄范围复审：尚未完全关闭（2026-11-04）

已核对提交、`report-command-presend.md` 与新增测试源码。`senderEntered` 分界正确，claim 有效期间 PAUSE/drain 的确定未发路径已修复；进入 Sender 后异常保留 UNKNOWN，无自动重发。但 `finish()` 仍要求 `attempt_until > db.now()`（当前 268 行附近），默认发送窗口只有 3000ms。若第二次检查前线程暂停或 SQL 访问迟缓超过该窗口，活执行者仍明确未进入 Sender，却无法写入 FAILED_BEFORE_SEND；`recoverAttempts()` 随后写 UNKNOWN，原 P2 后果依旧。报告原要求的到期证据收尾没有落实。

需要单独使用原 command_id+claim_token 收敛确定未发状态，不依赖未到期；同时保护 ACK、换 claim 及已进入 Sender 的保守语义。建议测试第二次 guard 时将 attempt_until=0，分别在/不在 recoverAttempts 已改 UNKNOWN 后触发 PAUSE，断言终态与 quiescent。现有测试只有未到期分支。此为同一 P2 的剩余分支，不重复计数。

## 追加故障语义审查：P2，HTTP 200 错误体会让 PC 宣称未执行写入成功

父任务真实依赖断链探测观察到 HTTP 200 错误体，本轮据此追踪调用链，未自行操作服务或浏览器。

- 全局 `GlobalExceptionHandler.handleRuntimeException()` 返回 `AjaxResult.error`，未设置错误 HTTP status。Redis/SQL 异常如果落到此处理器，会得到 HTTP 200、body.code=500。
- `pc前台项目/src/lib/files.js:25-29` 只检查 response.ok，错误体也被当作上传成功并返回 blobId。
- `pc前台项目/src/lib/guardian-events.js:22-29` 只检查 response.ok，之后忽略 refresh() 的 false，返回错误体。
- `pc前台项目/src/views/event/EventView.vue:144-147` 因此可删除未保存核验草稿，并显示“核验记录已提交”；照片链 182–185 也会显示“核验照片已保存”。这是可跟踪到用户结果的假成功，不只是 HTTP 约定不优雅。
- 新增维护面板将 `businessConfigApi.js` 返回的 200 错误体赋给 state；`clusterMaintenance.js:3` 将缺少 paused 的错误体显示为“正常运行 / 业务写入正常开放”。

Android `wear/api.dart:151-162` 同时检查 body.code，拒绝此类响应；PC snapshot `runtime.js` 的 readable(body.state) 也会标离线。因此不能概括全部客户端都错误，也不能用 snapshot 正确来推断写入路径正确。

修复可限定为 wearable/guardian/admin 业务接口的异常 HTTP 契约（避免改动整个旧 RuoYi 成功约定），并为上述关键写入/维护结果补语义或结构防御。实际 Redis/DB 依赖失败应返回可识别失败，PC 保留草稿、显示错误、无保存成功 toast；维护状态应为不可读取。父真实故障验收需重跑准确边界。本项与 transport P2 独立，当前合计 **2 项 P2，0 项 P1**，整体仍不可批准。最终 jar/真实两库仍待后续修复制品验证。


## 8dff7be 认领过期修正复审：原 transport P2 CLOSED

**限定修复 Approved。** 已核对固定提交 `8dff7be68e3e874d528e050f55f99f475ad6ab74`、前序 77886d7、两文件工作区无差异，以及实际 RED/GREEN 日志；未自行重跑构建或测试。

`finishBeforeSend` 只由活执行者的 senderEntered=false 分支调用，使用 command_id+原 claim_token 与 DISPATCHING/UNKNOWN 条件写 FAILED_BEFORE_SEND，不再要求原 attempt_until 未到期。因而既能在恢复前收敛，也能在另一恢复者已将同一尝试改 UNKNOWN 后收敛；不会覆盖已 ACK/REJECTED 的其他终态或不同认领。该证据更新不重新授予发送权限。进入 Sender 后的 finish 条件和异常 UNKNOWN 保持原样，进程死亡没有执行 catch，仍按原 UNKNOWN/no retry 语义处理。

新增参数用例覆盖 node drain、全局 PAUSE、到期且尚未恢复、到期且已恢复 UNKNOWN；断言 Sender 次数 0、确定失败终态、uncertainTransport=0、quiescent=true。现有 sender 抛错/no retry、early ACK、不确定中断等测试仍在。`command-presend-expiry-red.log` 读回 16 tests / 2 failures，均为预期 FAILED_BEFORE_SEND 实为 UNKNOWN；`command-presend-expiry-green.log` 读回 47 tests / 0 failures / 0 errors / 0 skips，BUILD SUCCESS（routing 16、media 27、control 4）。均为本轮聚焦/H2 证据，不改称真实 DM8/MySQL 或实际容器验证。

当前剩余 **1 项 P2**：上一节 HTTP 200 错误体的 PC 假成功语义，已由另一实现任务处理但尚未在本报告复审关闭。因此整体 Spec/Quality 仍需修正；仅 transport 原 P2 及其到期分支已经闭环。最终 jar 构建、真实两库/部署/故障验证继续由父任务在全部修复后按实际制品完成，不把旧 1f0b 运行时重新标为含本修复。


## 8d79d55 依赖错误语义复审：P2 CLOSED；全分支代码审查 Approved

**最终代码/规格决定：Spec Approved / Quality Approved，已知未关闭 P1/P2 为 0。** 当前审核固定版本为 `8d79d55fac1eaa03753e9577ad3b3b64ae47fd1f`，包括先前 77886d7 / 8dff7be 的 transport 修复。上文需修正结论为历史发现与逐次闭环记录，以本节最终决定为准。

只读核对提交、生产调用链、测试源码、报告和实际测试日志；被审生产文件相对此提交没有工作区差异。没有运行 Maven、服务、数据库、浏览器或修改实现。

- `WearableDependencyError` 仅限定 Guardian/mobile/media/business/maintenance/admin 控制器，并涵盖 MVC 会话拦截阶段；Redis/DB 资源不可用、查询超时、创建事务/事务系统异常返回真实 HTTP 503 与固定可读错误，不泄露异常细节。GuardianError Order 0、依赖 advice Order 1，早于旧全局通用处理器；原领域错误仍优先，非 wearable 控制器保留旧 RuoYi 契约。
- 事件 API 同时拒绝 HTTP 失败和旧 code>=400 错误体，验证回执事件 ID 与有效整数 version。确定回执前保留相同 pending requestId；错误响应不会再进入成功 toast 或删除草稿。有效提交回执足以确认写入，后续展示刷新返回 false 不应将该已确认提交误报失败。
- 文件上传只接受 `{ok:true,id:<本次ID>}`，与实际 GuardianController.upload 返回形状一致。旧 200 错误体、错 ID、无效回执均中断照片关联；不会再因为 HTTP 200 直接回传 blobId。
- 管理维护 read/change/reconcile 同时检查错误 code 和 paused/quiescent 布尔字段，失败时清空 state。新增状态不会再把错误体呈现为“业务写入正常开放”，核对失败也不保留可能过期的状态。
- MockMvc 使用真实 Controller、WearableWebSecurity、WearableSessions 与 advice，Redis/DB 边界故障使用受控 mock；包含拦截阶段上传未进入、管理会话 DB 失败、snapshot timeout、成功上传/维护形状、原 400/401 与 legacy HTTP200 错误契约。它不是实际 Redis/DM8 停机测试。
- EventView 组件级回归调用真实 submitVerify+事件 API，旧 200/code500 保留输入、无成功 toast，恢复重试沿用原 requestId，收到有效回执才显示提交成功；上传/维护错误和无效形状另有针对性测试。这些不是浏览器交互验收。

实际日志读回：`D:/DevTools/dm8-tmp/dependency-green.log` 为 42 tests / 0 failures / 0 errors / 0 skips、BUILD SUCCESS；`dependency-pc-front.log` 为 236 pass / 0 fail；`dependency-pc-admin.log` 为 487 pass（33 test files）。本轮仅读回，没有重跑或将报告中的 RED 直接改称亲自复现。

**保留的窄边界：** 此批准是代码与已有聚焦测试证据结论。最终 jar 尚待父任务统一构建；修复后的真实 DM8/MySQL、实际 Redis/DB/共享目录故障与恢复、浏览器无假成功结果及最终 artifact migration rebind，仍须绑定新制品单独完成。父任务正在进行的 Android/容量按各自实际证据结项；实际麒麟 V10 x86_64、NAS/NFS、物理设备/真实媒体、长时现场稳定性仍是独立外部门槛。不得把旧 1f0b 运行时标为包含 8d79d55，也不得将本报告 Approved 表述为完整系统或生产交付验收全部通过。


## 984fab2 单节点运维复审：Approved

最新限定审查提交 `984fab2786afb1d4f4a44f88cfaea57c5baf9563`，仅 `deploy/cluster/ops.py` 与 `test/test_ops.py`；两文件相对此提交无未提交差异。**全分支 Spec Approved / Quality Approved 维持，已知未关闭 P1/P2 为 0。** 未运行服务、Maven、AVD 或测试。

`verify_loaded_generation(restart_node)` 只将另一节点的 helmet/belt gateway 列为可缺失。目标节点网关与 wear/fuda/backend-router/ingress 缺失仍 fail closed；实际运行的对端网关仍检查 generation 标签与挂载哈希。调用仅在 targeted restart 成功完成 Compose --wait 后传入目标 node；full up 继续使用严格默认值。之前 `generation_window()` 对停止容器使用 --all 读旧标签的安全检查未削弱，因此不能借停对端跳过配置整代变更维护窗。缺少必需服务改为明确错误，也避免 docker inspect 空 ID。

新增命令级 mock 测试覆盖 A 停止时只启动 B、目标/共享入口缺失、停止 A 的旧标签、运行 A 的旧挂载、full up 缺少 A。`report-ops-single-node.md` 报告 Python suite 17 项通过；本轮核对测试断言但未独立重跑或读取到该次单独日志，因此按实现报告引用，不写成真实单节点 Docker 重启已在本复审通过。

最终迁移进展单独更新：已读 `report-migration-release-final.md` 和非敏感 `migration-release/verification-summary.json`，其中 source/DM 两包均绑定新 JAR SHA256 `35290a865fe8169bdaeeacab57151e379b7235a2808a4e7cbf0e8358158e8614`，99 tables / 28 rows / 4 files，三次 reconciliation COMPLETE、filesVerified 与 identityWatermarksVerified=true。实际恢复为 91 tables / 27 rows，其余 8 表 archive-only；不要写成 99 表均恢复。此前真实 kill/tamper 矩阵仍绑定 71ab732e，没有将其说成新 JAR 重跑。该新增 ops 修复不改 Java 制品。

因此上文“最终 jar 未构建/迁移 rebind 待执行”是先前阶段状态，现已有父任务最终制品迁移成功报告及摘要读回。本轮没有独立重算制品 hash 或重做迁移；最终浏览器/依赖故障/容量及 Android 当前进度仍由父任务按实际证据确认，麒麟/NFS/物理设备/现场长期稳定性门槛继续保留。


## MigrationInspect recovery fixture 补充复审：Approved（待父任务提交）

本次只读审查未提交的 `deploy/cluster/migration/MigrationInspect.java` 11 行增加，未修改或运行 fixture；HEAD 仍为 984fab2。**批准该测试夹具增量，未发现新增 P1/P2，产品 MigrationTool 与 Java 运行制品未变。**

- `seed-recovery` 在既有 disposable schema 配置门禁下运行，并要求 recovery 表为空；仅插入一条固定测试主键、虚构 node/actor 与中文/emoji/嵌套计数/大整数 JSON，不删除或覆盖现有行。不走 admin connection，也不改变表结构或 migration owner。空表 precondition 是测试防误用边界，不能单独证明任意连接配置都指向隔离数据库；实际端点隔离仍依赖既有 wrapper/父任务运行清单。
- `assert-recovery` 只读指定固定主键的 summary_json，缺记录或无法解析会失败，中文 emoji、nested UNKNOWN=2 和 revision=9000000000001L 均实际比较；不是仅 SELECT COUNT 的空断言。该定点断言仅覆盖这些 JSON 字段，完整行/全部表仍由正式 reconcile 的摘要与主键比较保证。
- 已读取最终制品运行的 `migration-release/target-check.log` 与 `back-check.log`，DM8 与 MySQL 各出现 assert-recovery PASS，随后各自正式 reconcile PASS；未读取或输出 private 配置。没有将已有日志改称本轮执行。

额外证据状态读回：`ops-single-b-final.log` 实际记录 Node b drain complete 与 running gateways/configuration verification 完成；本复审未亲自核对容器状态。`capacity-baseline/verification-summary.json` 为 COMPLETE，绑定同一 35290a86 jar，99 表 / 12246 行 / 5 文件，源对账 91 表 / 2731 行、8 archive-only，filesVerified / identityWatermarksVerified=true。该结果是完整应用基线备份/对账证据，**不是容量负载结果**；PC 最终故障与容量实际运行继续保留父任务边界。

## 7013eda 单节点首次启动补充：Approved

已在 `review-delivery-final.md` 末节完成 ops.py/test_ops.py 的窄代码审查及安装文档闭环。--node 使用显式服务列表与 --no-deps，默认双节点兼容，代次/预检/实际挂载校验保留；无新增P1/P2，全分支代码批准维持。11项为无Docker mock测试证据，真实single首次启动待父任务执行，不提前宣称通过。本ops提交不改变35290a86后端jar。
