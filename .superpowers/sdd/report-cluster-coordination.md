# Task 2 — 全局协调与事务交付报告（验证进行中）

状态：实现与主要隔离跨进程验收已完成，最终固定版本审查与完整应用验收尚未完成，**尚未标记全系统 DONE**。父任务负责最终真实浏览器/Android和完整双app部署验收。当前文档随验证更新，不把本地单测写成集群证明。

## 变更与接口

- `20261103_cluster_coordination`：wearable_cluster_work（resource/node/generation/token/epoch/DB deadline）、wearable_cluster_operation（operationId/kind/node/generation/state/DB lease）、wearable_media_effect（稳定fingerprint、operationId、claim、IN_FLIGHT/CONFIRMED/UNKNOWN/NOT_SENT、加密response）。mysql/dm8同构；既有migration未修改。
- `20261103_cluster_recovery`：wearable_cluster_recovery（recovery_id/node/generation/actor_id/reason/summary_json/created_at）。显式核对审计；不提供忽略未知结果的入口。
- SchemaLifecycle.BUSINESS集中注册两版本；集群启动只校验。configure额外拒绝已有schema_lock owner；通用validate供迁移恢复工具调用仍可用。SchemaMigration及bootstrap CLI使用单物理连接、finally destroy，避免每条DDL新连接。
- GET `/internal/cluster/live`始终200；GET `/internal/cluster/ready`校验node generation/DB lease、非drain、Redis、GuardianFiles.storageReady，独立单线程探测、1.5秒上限、1秒正结果缓存；不初始化存储、不执行调度。
- POST/GET `/internal/cluster/drain`恒时验证32-byte以上base64url管理令牌；未配置拒绝。POST幂等202；GET真实activeWrites/unknown/quiescent。节点drain不写全局PAUSED；新登录/工作/admission/dispatch拒绝，已有raw receipt允许恢复。
- 原 `/api/admin/v1/maintenance`返回全局状态，PAUSE提交即拒绝新业务，不等待本JVM计数冒充全部节点。新增POST `/maintenance/reconcile`仅demo-system，要求PAUSED与10–500字依据，读取签名媒体operation evidence；只有无外部未知且旧generation已失效，才把孤儿permit记RECOVERED并写审计。健康旧generation绝不自动完成。未核对完全的尝试仍记录审计并返回RECOVERY_UNCONFIRMED，不清理孤儿permit。
- `local-dev/helmet-media`新增HMAC保护的GET `/operations/<fingerprint>`，成功写结果落盘后才返回。缺证据404；Java端仅读证据，不重新POST/PUT/DELETE。响应中的私有凭据在SQL以AES-GCM共享密钥加密。
- 后台Layout为系统管理员添加折叠“系统维护”：全局暂停/恢复、活动/未知/待处理上报、核对依据及显式核对；待确认/排空中/已排空分别展示。单节点drain明确留给内部运维接口。

## 锁与故障语义

1. 全局逻辑资源粗粒度media保护媒体+Guardian写投影+ledger writer；platform→media允许嵌套，quartz:job→业务资源允许嵌套。所有资源以DB时间、generation、随机token、epoch fencing，前台等待最多5秒，后台冲突明确skip。旧node lease失效可接管工作租约，但不接管未决外部副作用。
2. JVM局部次序：媒体monitor（若需要）→WearableBusinessStore.transactionLock→cluster_control SQL锁→work/permit检查→receipt/business meta→ledger meta→相关档案SQL。网络调用不持SQL事务。raw receiver只读SQL namespace＋内存台账投影捕获context，不获取media租约/permit、不发布投影；BUSINESS_LOCK→control顺序保持任务1契约；媒体receipt先media monitor再BUSINESS_LOCK，避免反锁。
3. ledger.mutate在同DataSource短事务锁meta一致读，回调内重新鉴权/领域版本/幂等/preview，规范化新行，revision CAS R→R+1、数据/审计/idempotency/关联hat/external/syncRecords同提交。无改动重放不增版；replaceExpected拒绝旧快照；cluster裸write拒绝。ClusterDatabase、AdminLedgerStore、WearableBusinessStore、ExternalDataStore的SQL事务均设10秒超时。
4. GuardianMaster/Platform是提交后可重建的单调投影，appliedLedgerRevision阻止旧版本覆盖；人员删除只清ledger来源映射，保留历史证据；移除ledger回调内Guardian发布与跨store monitor。
5. 工作/permit独立daemon续租；每次SQL写与下一外部effect前重新检查。未知外部执行从不由租约过期推定失败；IN_FLIGHT/UNKNOWN、失联permit、transport未知、推送IN_FLIGHT阻止全局quiescent/import。只允许原始回执/真实云证据解决，禁止自动盲发。活执行者明确尚未调用sender的前置门禁失败记NOT_SENT，下一合法claim可执行；claim后进程被杀仍IN_FLIGHT，不能据租约过期推定未发。
6. 外部物理socket写/云服务内部副作用与SQL不能组成分布式原子提交；本实现不宣称端到端exactly-once。没有可确认读证据的操作保持UNKNOWN，须核对外部实际结果，不能直接导入或停机假报成功。

## 全入口 writer/effect/维护映射

|入口/方法|资源与事务|外部effect及恢复|维护行为|
|---|---|---|---|
|HelmetMediaService command/live/gbAcquire/gbRelease/gbLeaseStatus|media；持久业务意图→外部→带fence写回|同设备共享stream；viewer/GB独立demand；内部推流复用task1稳定purpose|新工作拒绝；GB GET可能释放也受控|
|provision/pendingAccounts|media；账号/密码先SQL保存|PUT账号经journal；重启从无sipHost持久账号和wearable_device_owner成功登录行恢复；单账号失败保留待办、不阻断其他媒体恢复|PAUSE/drain禁止新effect|
|call/endCall/resumeStreams|media；callId先保存|PUT operator/POST call/DELETE均journal；resumePending持久化，失败保留|保留通话能力，未知不重建call|
|reconcile/applyEvent/startPendingRecordings/reconcileCalls/reconcileRecordings/expireViewers/expireGbLeases|media；事件业务变化+cursor同SQL事务|查询可重试；录像POST稳定requestId、UNKNOWN不再次发送|background skip/暂停；每节点独立只读health|
|command/receipt/saveCommand|media→receipt事务→business CAS|保留result/receiptAt及终态；transport ACK不替代业务结果|原始回执继续持久接收；恢复沿原context处理|
|GuardianStore snapshot/projectPlatform/update/mirrorHats|media + business CAS；允许纯查询PAUSE|本地SQL投影，无外部I/O|GET也不绕过fence；PAUSE读既有状态|
|WearableReportDelivery recover/deliver|media recovery；receipt FOR UPDATE+handler+processed同事务|原始report持久，按sequence恢复，不重捕获佩戴人|PAUSE停止业务投影，保留raw接收；node drain允许已入队恢复|
|HelmetEventDelivery.retry|media，保留event去重|本地持久恢复|全局permit|
|GuardianMobileCommunications start/joined/end/broadcast/reconcileInvalidSessions|media共享calls/媒体控制|权限失效产生稳定终止意图|新业务拒绝，权限复核保留|
|PlatformStatusPoller.refresh / AdminPlatformService.sync|platform外部preview→media+ledger短事务|preview为可重试读，external记录与syncRecords同提交；重读最新绑定/权限|manual/自动一致，PAUSE不发新preview|
|FudaPushDispatcher.drain/reconcilePresence|outbox token lease多worker；DB时间；全程permit；Guardian投影走media|保留已约定事件重试及去重；不套用媒体盲重试|新发送检查PAUSE/admission；调用sender前拒绝用原token releaseUnsent退PENDING，即便lease已过期；换token则拒绝旧收尾；实际网络重试契约不变|
|两个gateway expireConnections|每节点本地连接清理，task1 OwnerToken条件release|不全局选主而遗漏socket|raw/连接生命周期不被PAUSE截断|
|Quartz AbstractQuartzJob实际调用（含SysJobService.init/run）|quartz:job DB lease + durable firing hash|已确认firing不重放；IN_FLIGHT/UNKNOWN不重放；执行前拒绝可记NOT_SENT；错过竞争本轮skip，下一fire可正常执行|手工与自动同一bridge，保留任务能力|
|AdminAccess/Assignment/Master/Maintenance/Device.execute|ledger.mutate，各领域版本/引用/当前授权/幂等在锁内|仅本地SQL；Master先在media资源下取工作证据，回调不进Guardian|permit覆盖整次业务；当前撤权后重放拒绝|
|AdminLedgerStore read/importInitial/fixture replaceExpected|meta锁一致读取；validate缺标记/待迁移拒绝|显式bootstrap单次空库，旧快照不覆盖|PAUSE禁止迁移/fixture写|
|WearableBusinessPolicy.configure/构造初始化|version CAS；legacy schema稳定锁下feature+config同事务|本地SQL|validate缺config失败，不能启动自动填充|
|ExternalDataStore.record/put|schema稳定锁+方言原子upsert，同DataSource调用事务|首次同key不竞争插入；空localId不覆盖已关联ID|coordinator fence，无网络|
|WearableWebSecurity / command admission+dispatch|全局durablepermit / control行串行|dispatch复核当前身份/权限/设备生命周期/领用版本，内部推流读当前人/GB demand|PAUSE与begin串行；drain拒绝新dispatch|
|FudaGbInternalController.authenticate|Redis NX TTL121s（验签后claim）|共享nonce；Redis异常503，保留FudaRedisNonceStore601s|不降级JVM缓存|
|AdminAccessService.preview/checkPreview|Redis5min actor/revision/type/完整canonical fingerprint；锁内Lua消费|消费后SQL/commit异常首次返回PREVIEW_CONFIRMATION_UNCERTAIN，明确先核对、保留operationId、未生效重新预览；既有operationId重放遵守当前权限|Redis错误fail closed|
|WearableSessions/RuoYi TokenService|共享Redis namespace配置；WearableSessions每请求核credentialVersion|跨节点验证/撤销，无本地降级|PAUSE保留登录；node drain拒绝新登录|

## 离线空库 bootstrap

入口`com.ruoyi.guardian.WearableBusinessBootstrap`，唯一参数为私有目录绝对路径。输入：admin-ledger.json、guardian-state.json、helmet-media-private.json、business-config.json、feature-acceptance.json（可空数组）。环境MELHAT_DB_PRODUCT/URL/USERNAME/PASSWORD、MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY；不把凭据放命令行、不打印。media key必须非空白且Base64解码32字节（即便media={}）；每账号必须已具显式BCrypt hash；不生成默认凭据，feature acceptance必须给evidence。

先运行SchemaMigration。bootstrap验证全schema，claim持久schema owner（启动禁止），锁cluster control并拒绝有效node、operation/effect/transport/raw report及任何已有meta/namespace/master、external_integration/external_data_record/safety_hat_info/fuda_push_outbox数据，事务一次提交ledger、guardian/media namespace、policy、feature、global runtime。已有数据无marker也拒绝。失败回滚全部；进程被杀留下owner，需离线核对，不能自动覆盖。父任务用于独立全新lab schema；禁止对日常环境操作。

## 已获得证据（截至本次更新）

- `coordination-broad-fifth.log`：631 tests，0 failures/errors，4 skipped（环境条件）。包括已有单机MySQL语义的H2单测；不是DM8证明。
- `coordination-cloud-contract.log`：helmet-media Node 30 tests通过；operation evidence签名、属性顺序稳定fingerprint、持久重载、缺证据404、不重写。
- `coordination-admin-ui-final.log`：维护展示/API测试与businessConfig用例5条通过；`coordination-admin-build-final.log` Vite build通过，包含最新核对按钮。真实浏览器由父任务验收。
- `coordination-bootstrap.log`：3 tests通过（一次初始化/拒绝覆盖、不给默认凭据、晚失败全回滚、未知操作拒绝）。该批为H2语义单测。
- 首轮真实DM8 `coordination-dm8-1793763213214/evidence.json`：A66296/B27716；ledger、maintenance、Redis、fence、UNKNOWN。
- 真实DM8扩展 `coordination-dm8-1793764046865/evidence.json`：A42600/B13324；early receipt完整result/receiptAt未覆盖，provision/call各1次写。
- 真实MySQL首轮：A9892/B20200，kill64536；媒体同样通过，并确认kill回滚/孤儿permit阻止quiescence/Quartz2次合法firing/node-local drain。该Maven总命令受旧projection fixture断言失败影响，不能报整条green；后续fixture已在广回归修正。
- `coordination-dm8-events3.log`真实DM8 BUILD SUCCESS（1完整矩阵）：A10744:59954/B67204:53229；事件事务kill34720、SQL写kill64916、TCP故障60996。event/cursor杀进程回滚与重放单调，mixed viewer/GB，recording未知POST1次，provision1/call1/timeout1，真实SQL/Redis节点专属TCP断开fail closed、Quartz2次合法firing、drain不全局暂停。全部子JVM最终终止。
- `coordination-mysql-writers.log`暴露新行规范化遗漏：真实Master create后下次cluster read把缺模型字段判待迁移；已把规范化放在ledger显式提交事务，`coordination-mysql-writers2.log`完整6 tests通过；MyBatis hat/external/syncRecords同事务回滚、真实六类writer已验证。
- 一轮DM8启动测试在编译时人工终止（events2）：父确认隔离DM容器原1.5GiB cap OOMKilled/137；父保留volume恢复到2GiB。events3在恢复后跑通。没有通过关闭媒体/Quartz规避；此资源调整需记录于容量实验。

## 审查修复后的实际证据

- `coordination-dm8-review1.log` BUILD SUCCESS，29 tests（包括真实双JVM完整矩阵、bootstrap6、Fuda7、Access HTTP14、真实Quartz job entry1）。`coordination-dm8-1793770905925/evidence.json`：A PID67412/port49202，B10280/57301；event kill49988，SQL kill52748，TCP IO5308。新增queued领用撤销不发送、原始接收不抢media租约、drain已有连接仍保存raw、claim后PAUSE确定未发NOT_SENT、角色/凭据同版本仅一提交且败者VERSION_CONFLICT、旧session跨节点失效、旧投影不能压新版本。
- `coordination-mysql-review3.log`：真实矩阵通过，`coordination-mysql-1793770780739/evidence.json` A13668/58240，B52356/64345，event kill64636、SQL kill37840、IO37476。该总命令有一条Mockito重设fixture NPE；已用doAnswer修正，并在上条DM命令14个Access用例全部通过，不能把此MySQL总命令标green。
- `coordination-broad-final1.log` 649 tests的5个录像回归失败定位到新增pendingAccount恢复异常中断整轮媒体reconcile；改单账号保留待办且继续事件/录像处理，`coordination-media-pending-fix.log` 22个ClusterMediaIntegrationTest全通过。仍需最终广回归读回。
- SafetyHatInfo实际DM MyBatis新增曾报IDENTITY_INSERT错误（默认显式生成ID），已仅将该实体id标IdType.AUTO。`coordination-dm8-writers3.log`及review1均真实DM通过，MySQL实测创建/并发修改/平台sync/关联SQL rollback继续通过。已实测AUTO mapper范围仅SafetyHatInfo，包含GuardianHatArchive和PlatformDeviceSyncService调用；未做全局id-type修改，不把其他AUTO实体称为已验收。
- 媒体全份导入额外拒QUEUED/PREPARING/SENT；node drain与Guardian-only导入保留原门槛。SENT仅代表socket返回，不代表设备成功，也不授权删除业务命令及捕获context。

## 最终回归与复现入口

- `coordination-mysql-all-final.log`：BUILD SUCCESS，649 tests / 0 failures / 0 errors / 6 skips。跳过为专用RealDm8ContractTest、RealMySqlContractTest、FudaPushMySqlTest 3例及GuardianSharedFilesTest；这些类需要各自独立环境开关，不把它们当已运行。本批真实MySQL task1与coord两类都运行。
- MySQL路由 `cluster-process-2597992939160728987/evidence.json`：PIDs45820/61180/12348/40060/44808；真实WS、远程状态、单投递、幂等冲突、接管事务屏障、晚close、restart queued、early ACK、前后send kill UNKNOWN、不重发、DB获取失败、重复登录token、belt接管、墙钟±2h、TTL、drain。
- MySQL协调 `coordination-mysql-1793771265277/evidence.json`：A45680:49684、B45436:50882，event kill49444、SQL kill2120、IO12308。新增真实Redis预览TTL/修订失效、消费后SQL错误后立即明确恢复提示、同operationId并发只增一次revision、撤权后已提交幂等请求拒绝；nonleader健康、持久登录恢复provision、旧投影不回退。隔离schema累计恢复审计记录7条（含未核对完全尝试），所有子JVM最终退出。
- `coordination-dm8-all-final.log`：BUILD SUCCESS，35 tests / 0 failures/errors，任务1的22媒体+11路由contract+1真实路由+1真实协调矩阵均通过。DM路由证据`cluster-process-2081964011713723058/evidence.json`。两库均为共享真实DB和Redis16379/db3，只有设备/云端为loopback替身。
- 后端全suite命令：在B设JAVA_HOME，ROUTING_CONNECTION_FILE指向私有MySQL配置、COORDINATION_REDIS_FILE私有Redis配置、COORDINATION_OUTPUT=W/output/dm8-cluster，然后运行`mvn.cmd -B -pl ruoyi-admin -am -DargLine="-Xmx512m -Djdk.net.unixdomain.tmpdir=D:/DevTools/dm8-tmp -Djava.io.tmpdir=D:/DevTools/dm8-tmp" test`。DM上述35例命令加`-Dtest=ClusterRoutingContractTest,ClusterMediaIntegrationTest,RealClusterProcessTest,RealCoordinationProcessTest -Dsurefire.failIfNoSpecifiedTests=false`。
- 可复用脚本`ruoyi-admin/src/test/scripts/run-cluster-coordination.ps1 -ConnectionFile <私有配置绝对路径> -RedisFile <私有Redis配置> -OutputDirectory <output目录>`；主动拒绝非WEARABLE_TEST/wearable_test账号或非16379Redis。该fixture清理隔离schema测试行，禁止对业务schema运行。路由旧脚本仍可用；本次路由证据通过COORDINATION_OUTPUT写入output目录，JVM temp继续ASCII目录。

## 构建产物

`coordination-package-final.log`：`mvn.cmd -B -pl ruoyi-admin -am -DskipTests package` BUILD SUCCESS（测试已在上述命令独立跑完，package不重复运行）。实际jar `后端代码/melhat_server-dev/ruoyi-admin/target/fdc-admin.jar`，110207413 bytes，SHA256 `71AB732EDD82DED8C0472CF5D88555BBAE6E5B77483C3FC100D5CF1D5C65A7BB`。jar tf已确认bootstrap/coordinator及mysql/dm8 recovery SQL均打入。

额外真实Fuda屏障 `coordination-dm8-push-final2.log` BUILD SUCCESS；`coordination-dm8-1793771627043/evidence.json` A27064:61525/B5396:53601，event kill55660、SQL kill63420、IO6408。真实dispatcher/capture/outbox/sender、共享SQL：A领取后屏障，B暂停，原claim deadline设为已过期，A明确未调用sender，按原token释放PENDING；保持PAUSED时quiescent=true且网络0；B恢复后原事件发送1次并DELIVERED。已换token的旧未发释放拒绝另由Fuda7条单测覆盖。该新增fixture首轮仅编译引用package-private工具失败，改同包FudaMapping后完整green；生产代码无变化。


- 新推送屏障MySQL `coordination-mysql-push-final.log` BUILD SUCCESS，`coordination-mysql-1793771826849/evidence.json`：A67412:64558，B63848:51827；pushPauseAfterExpiredClaimReleasesAndResumes=true，完整既有matrix同步通过。所有子JVM已退出。

## 待补证据与交付边界

最新真实Redis预览、两库task1路由与广回归均已通过；新推送PAUSE屏障DM/MySQL均通过；package已产出。完整应用健康依赖中断/浏览器/Android由父任务最终验收。不会把本文件写成全系统完成证明。

## 代码变更方法表（主要方法）

|文件/模块|主要新增或调整方法|
|---|---|
|ClusterWorkCoordinator|runPeriodic/tryAcquire/renew/release/run/runRecovery/fenced/beforeEffect/begin/end/status/evidenceWrite/recoverAbandoned|
|MediaOperationJournal|execute/resolve/reconcile/canonical/AES-GCM response保存|
|ClusterControlController|live/ready/drain/drainStatus/authorized|
|ClusterQuartzExecution、AbstractQuartzJob|execute（共用自动/手工实际job invocation）|
|SchemaLifecycle/SchemaMigration|configure启动owner门槛、validateOnly、BUSINESS资源、单连接迁移CLI|
|WearableBusinessBootstrap/AdminLedgerStore|initialize/initializeEmpty、mutate/readSnapshot/read/replaceExpected/CAS规范化提交|
|6个Admin*Service|execute→mutate；Platform preview→merge；Master工作快照与去除提前publish|
|GuardianMasterProjection/PlatformProjection|apply revision单调/删除来源保护|
|WearableBusinessStore/HelmetMediaStore/GuardianStore|receptionSnapshot/save/processReport/atomic/snapshot/update/mirrorHats fence|
|HelmetMediaService|媒体全部mutator wrapper、health、saveCommand合并、applyEventSaved原子cursor、resumePending|
|HelmetCloudClient/helmet-media server|request journal / signed GET operations evidence|
|WearableMaintenance/Controller/Import|durablepermit、global pause/status、reconcile、import排空guard|
|FudaPushDispatcher/FudaPushOutbox|drainActive/releaseUnsent，已发仍原finish token+lease规则|
|FudaGbInternalController/AdminAccessService/WearableSessions|Redis nonce/preview Lua、credentialVersion与drain admission|
|ClusterMaintenanceGuard/DeviceCommandRouter|当前权限/领用/内部stream demand复核及取消未发送命令|
|PC Layout/ClusterMaintenancePanel/clusterMaintenance/businessConfigApi|管理员全局维护及未知状态提示/核对动作|
|CoordinationProcessNode/RealCoordinationProcessTest/CoordinationBusinessFixture/TcpFaultProxy|真实双JVM/屏障/kill/MyBatis事务/独立SQLRedis断链fixture|
