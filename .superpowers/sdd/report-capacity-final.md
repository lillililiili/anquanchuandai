# 最终容量验证：待验收（用户已延期）

**PENDING_USER_DEFERRED：没有有效负载结果。** 用户明确“先保留容量测试为待验收”后已停止全部容量执行。首次隔离准备已建立网络、10个未启动容器、只读媒体快照、专用只读monitor和空容量schema；导入因Windows标记CRLF导致文件摘要不一致失败。只读核查确认业务行回滚、schema owner为空，原失败journal/targetId/38字节marker完整保留。没有启动app、预热、测量、reset或DROP；不声称单/双对照、持续容量或ops --node a真实首次启动通过。后文保留各阶段历史事实，以本状态与末节收尾为准。

已读deploy/cluster/CAPACITY.md、protocol-cluster/benchmark.mjs、sample-resources.py、DatabaseMetrics.java、migration/README.md及实际迁移对账输出结构。所有准备脚本位于 `output/dm8-cluster/capacity-final/`，详细前置条件和命令见其中README.md。

## 已知基线和执行门槛

父已报告1f0b9939应用库原849回执全处理、424定位和1SOS/link/event稳定；这只是父业务正确性验收事实，不是容量结果。当前WEARABLE_MIGRATION_LAB1104B、RedisDB6、wearable-validapp-shared仍为父工作对象，本脚本明确拒绝作为容量测试目标。

开始前需父明确释放并完成：

1. 停现有模拟器和PC/Android请求，确认无积压/未知副作用；离线PAUSE→排空→停全部app→租约失效后，用最终jar导出同一完整COMPLETE迁移包。
2. 为每轮正式恢复与reconcile同一包到WEARABLE_CAPACITY_*，独立Redis DB（拒0/3/6）和共享目录；独立媒体存储/operation证据另备份恢复。不能使用bootstrap近似快照。镜像digest、JAR、99表内容/identity/files摘要、媒体基线必须固定。
3. 父实际部署并核对总额相同的资源；脚本只读docker inspect，不代为修改。单app2CPU1800MiB/Xmx768m；双app各1CPU900MiB/Xmx384m。单两个协议gateway各1CPU512MiB；双四个各0.5CPU256MiB；总2CPU1024MiB。Xms总256m、MaxMetaspace总384m。所有公共依赖镜像/容器/资源固定；单模式停闲置B peers并核对路由。
4. 新lab attestation/独立配置与真实4个已注册领用设备（两帽两带）、同一合法GET账号/权限和足够TTL的私有session。沿用既有ops隔离证明，不能仅靠名称/loopback。
5. 只读监控账号能查询V$TRXWAIT/V$TRX；无自动GRANT。共享DM保持3GiB，约80%占用不是容量保证。限制临时schema数量，重建/清理只能父明确操作，不允许无限增加副本或停共享DB。
6. 私有plan内容锁定后，父提供带plan SHA256、baseline SHA256、明确释放消息引用、UTC期限的release文件。模板authorized=false、preparedOnly=true，默认不运行。每轮单独release；当前没有任何授权文件。

## 计划轮次与测量口径

single5m→相同快照恢复→dual5m，均先60秒预热、清零pending后开始。仅在对照有效并经父接受后，再从相同快照分别single15m/dual15m，不能用短跑替代持续运行。900秒计划必须引用通过的5分钟comparison且artifact/tools/负载语义相同。

现benchmark只发无坐标心跳、HTTP闭环最大速率；因此本目录准备独立变体capacity-driver.mjs，保留原工具隔离attestation与一连接一个待ACK的安全规则，增加固定坐标和runId/单设备sequence标记、逐设备attempt/ACK、固定HTTP节拍。未改原benchmark。

负载为四设备各最大1report/s、含固定经纬度；2个GET线程各500ms，合计最大4GET/s。HTTP建议`/api/admin/v1/state`且验证state对象。无SOS/设备控制/媒体写。延迟含失败尝试；响应ACK仅证明durable receipt，不表示业务处理完成。节拍超期/错误/重连问题如实记录；错过GET节拍或report响应超1秒不能算同等负载完成。

容器5秒配置采样，DB锁等待/最大当前等待/活动事务1秒配置采样；工具本身耗时计入实际间隔，离线报告记录实际跨度/最大gap，拒跨度<测量80%、容器gap>15秒或DBgap>5秒，不把缺样填0。DM是共享隔离实例瞬时统计，短等待可能漏采；需父停止其他schema负载，不能称单schema累计等待。连接池等待/慢查询没有新增采集，不声称已覆盖。

主机可用内存>=2GiB才开始。运行中主机可用<1GiB或DM内存>=90%，连续3个5秒guard样本时终止仅本轮启动的Node/Java/Python子进程，保留失败结果，不停止容器或共享DB。容器OOM/重启/资源变化/监控失败/业务错误/积压未清均拒有效容量结论。

## Durable回执与业务对账

CapacityReadback.java只执行SELECT。每设备精确核对attempt=ACK=带runId接收数=processed，sequence无重复；全设备原始行增量也必须相等，识别其他模拟器污染。帽legacy定位与helmet_location_fix增量等于帽报文数；alarm/SOS不新增；未知媒体effect为0。负载停止后最多120秒等待pending清零，再次只读检查计数稳定。不删原始报文、不改processed标记、不强行清队列。文件完整恢复靠正式migration reconcile；结束文件清单仍需父补证，不以SQL对账代替文件验收。

## 准备产物/方法

|文件|方法/作用|状态|
|---|---|---|
|capacity-driver.mjs|validateBenchmark/benchmark/deviceWorker/httpWorker；固定位置负载、节拍、逐设备计数、隔离证明|准备；Node --check通过，未执行|
|run-capacity.py|validate_plan/inspect_resources/resource_sample/readback/settle/main；授权/快照/资源校验、预热、采集、止损和对账|准备；Python AST通过，未执行|
|CapacityReadback.java|main/count；限定schema的只读原始回执和业务计数|JDK17 javac静态编译通过；main未运行|
|compare-capacity.py|compare/metrics；离线核对同快照、资源、镜像、工具和负载并汇总指标|准备；Python AST通过，未执行|
|plan/workload/release.template.json|无具体方法；私有参数、授权模板|占位，不可直接执行|
|resources.single.json/resources.dual.json|无具体方法；候选Compose资源覆盖|未应用|
|containers.example.json|无具体方法；实际容器ID/镜像/资源清单格式|示例，须列齐全部公共依赖|
|README.md/prepared-files.sha256.json|前提、步骤、证据边界和准备文件哈希|已写|

静态检查命令：Python ast.parse全部.py、json.loads全部JSON；`node --check capacity-driver.mjs`；`javac -J-Xmx128m -encoding UTF-8 -cp static-check/* -d static-check CapacityReadback.java`。classpath只从固定1f0b9939 jar提取fastjson2，未下载依赖、未运行Java main、未接数据库。真实环境权限/路径/SQL适配仍须获释后的首次预检确认。

## 后续执行入口（仅父释放后）

```powershell
python output/dm8-cluster/capacity-final/run-capacity.py <private-plan.json> --execute --release <private-release.json>
python output/dm8-cluster/capacity-final/compare-capacity.py <single-run-dir> <dual-run-dir> <new-comparison.json>
```

结果目录 `capacity-final/runs/<runId>` 禁止覆盖，包含资源/DB原始样本、四设备/GET延迟与吞吐、收尾SQL计数、guard和失败原因。private子目录含token输入，必须保持ACL，不能公开打包。当前没有runs目录中的有效测量结果。只允许结论“此主机、同资源、四设备、给定速率/时长”的实际表现，不外推设备规模、扩容倍数或麒麟生产容量。


## 专用容量部署准备与本轮释放

O/private/capacity-deploy 已按984fab2复制41个tracked部署文件，214879 bytes；逐blob核对通过，私有ACL已验证。新增capacity-stage.py、CapacitySchema.java、CapacityMonitor.java、capacity-media.py、capture-plan.py和三轮唯一targetId/journal配置；README.capacity.md列出完整阶段及未验证边界。16项纯离线guard单测通过；两个独立Java守卫javac编译通过，没有运行main/JDBC。capacity-final/driver-cutoff.test.mjs 两项VM/假WebSocket离线测试通过：截止后等待已发送ACK，超时保持失败，不伪造ACK。

冻结基线manifest SHA09076c923c76db8d5e287bf21f0897be88b344b70a207ec1dbd2121fc4eff99b，最终35290a86 jar。父已释放仅首次IF ABSENT创建、最小监控授权、还原与single5m；release-single5m.json明确不含reset。reset/DROP和dual需独立review与父后续释放，本时点未执行任何运行变更。准备证据见output/dm8-cluster/capacity-final/deployment-preparation.json。连接池单12/2/2、双各6/1/1已获父批准；同时保持CPU/内存/JVM堆总额相等和TLS参数。

### 首次运行前置：资源停止，无容量变更

先因冻结基线旧app-a ID已被父最终故障验收重建而拒绝；随后依据父最新final-original-apps-stopped.txt，对全部10个当前容器逐一核对完整ID、project、Exited，app镜像35290对应ID、LAB1104B/Redis6及连续性密钥一致，记录private/original-stop-identities.json，未修改冻结baseline。第二次前置在network动作之前因HOST_RESOURCE_STOP停止：hostAvailable1393.61MiB <2048，DM531.1MiB/3GiB(17.29%)。证据private/capacity-deploy/private/resource-stop-before-network.json；无新网络、schema、monitor、Redis7写入或负载。

新增低资源收尾保护：stop/pause不受启动内存门槛阻挡；真实默认路径及守卫离线测试现17项通过。全部新入口执行由同一Windows文件锁互斥。reset/DROP仍无授权、未执行，等待父review与单独释放。


## 独立审阅修复：离线完成，尚未测量

reset_paths 在 DROP 之前拒绝共享根/归档异常、下一轮目录/journal 已存在、schema/endpoint/固定 DB ID/密码连续性/targetId 不符及已开始的 reset。保留所有旧文件，不递归删除。capture-plan 合并原 10 服务并保存全部完整 ID；runner 在实际资源检查中拒绝已替换或 Running/Paused/Restarting 的原服务。

设备驱动使用跨重连保持的绝对时间表，记录意外断线与跳过的槽位。runner 的预热/测量与离线 compare 共用 capacity_contract：300 秒每设备精确 300 次并全部 ACK、认证 GET 精确 1200 次；900 秒相应为 900/3600。任何重连、意外断线、少发、跳槽或 cadence overrun 均不形成有效容量比较。截止后仍有界等待已发送 ACK，ACK 仍仅代表 durable receive，业务完成由 SQL 对账确认。

验证命令 `python output/dm8-cluster/capacity-final/verify-preparation.py`：22 项准备守卫、7 项负载契约、10 项业务止损、4 项实际 driver 函数的 VM 事件测试通过；包括独立 compare 对 300 vs 200 少发的拒绝，以及成功 ACK 后空闲断线的记录。Python AST/Node syntax 通过。原始命令与输出见 `capacity-final/review-fixes-verification.json`。这些测试不连接网络、数据库或容器。父随后暂停首次 provision，等待 ops 单节点 up 补丁同步；未执行任何 DROP、还原或负载。


## 用户延期后的最终收尾

用户明确延期后未再进行数据库恢复、新attempt、导入、重置、DROP、启动或负载。只读Docker核对：容量10容器均created且未运行；父原10服务仍停机且完整ID未变；DB/Redis/media/static公共依赖完整ID/镜像/资源与准备绑定一致。media从未被本轮暂停/停止，当前仍同一ID、Running、Paused=false。证据 `output/dm8-cluster/capacity-final/public-evidence/readonly-stop-state.json`。

失败原因：marker原生成使用Windows文本换行，目标38字节CRLF，冻结包37字节LF，迁移工具按SHA拒绝 STORE_MARKER_MISMATCH。只读102表回查非零仅 fuda_alarm_journal_state=1、wearable_cluster_control=1、schema_history=10、schema_step=236、schema_lock=1；其他业务行0，owner=NULL，未开始reseed。失败journal保持 ROWS_FAILED_OR_COMMIT_UNCERTAIN，不改写或复制绕过。准备脚本改为按字节复制并核对冻结包标记，但失败目录/marker未修改；该创建修正尚未重新运行。经明确授权、复核空目标与保留旧attempt后可准备新attempt，当前未授权且未执行。

monitor仅新建 WEARABLE_CAPACITY_MONITOR 并显式授两事务视图SELECT。DM默认PUBLIC和CREATE SESSION原样记录；仅对该新账号执行服务器 READ ONLY，不修改全局PUBLIC/SVI或其他账号，没有DBA/RESOURCE。实际两SELECT通过，业务表零行UPDATE被-5504拒绝，CREATE TABLE被-6506“试图在只读事务中修改数据”拒绝，零行系统对象DML被-2754拒绝；没有产生探测表。语法依据[达梦官方用户标识与鉴别](https://eco.dameng.com/document/dm/zh-cn/pm/identification-authentication.html)。默认角色存在不写成“只有两项可见权限”；测量器只使用固定SELECT且本轮未启动采样。

公共交付白名单位于 `capacity-final/public-evidence/whitelist.json`，含summary、只读停机身份和无真实凭据的负载/比较/止损/只读采样回读源码，不含private配置、token、release、provision/reset配置、数据导出或原始私有日志。没有资源/DB时间序列或单双比较文件，因为负载从未运行，不能用空文件冒充有效数据。源码快照7013eda与最终35290a86 jar不变；新增ops首次单节点启动只接入wrapper、未实际调用。

父收尾补充：上述public-evidence停机身份在公共依赖停止前采集。确认所有容量子进程退出后，父仅正常停止本任务DM8、Redis、media、static四个容器；测试MySQL此前已停。容器ID及数据卷保留，未删除数据。最终证据为 `output/dm8-cluster/final-dependencies-stopped.json`；日常melhat后端/MySQL/Redis只读核验仍运行。容量仍待验收，无后续导入/启动/负载。
