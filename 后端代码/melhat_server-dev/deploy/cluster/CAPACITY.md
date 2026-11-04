# 隔离容量测量流程

这些工具生成实测数据，不代表已经完成压测，也不预先承诺设备数或扩容倍数。

1. 按 [README 的实验室步骤](README.md#实验室独立配置) 准备独立数据库、Redis、文件卷、入口端口和预登记的 `900xxxxxxxxxxxx` 模拟设备。真实推送、真实设备控制必须隔离；保持被测业务功能真实可用。先完成双节点正确性及故障验收，再测吞吐。实验室部署单独生成 `labId` 和32-byte base64url `isolationProof`，保存在私有负载文件，运行 `node deploy/cluster/prepare-lab-entry.mjs <private-workload.json> deploy/cluster/private/lab/Caddy.lab`。`clusterctl.sh --lab ...` 只使用 `.lab.env`、`private/lab/*` 和 `compose.lab.yml`，强制入口只绑定loopback，需Compose>=2.24.4。运维工具核对登记的 Docker 实例及网络 ID、数据库/schema、Redis database、共享目录与配置摘要，并拒绝复用本目录正式配置的依赖实例。生产Caddy配置不包含实验室证明。驱动先从入口核对独立部署的实验室身份和证明，匹配前不会建立设备连接或访问业务GET；本机地址和设备编号本身不构成隔离证明。不得给日常/生产入口安装此实验室配置。
2. 固定数据量、业务关系、索引、数据库/Redis/共享盘资源、镜像摘要、网络和客户端机器。单节点与双节点的 **应用总 CPU、总内存、网关总资源必须相同**。例如两节点各1 CPU时，对照单节点需2 CPU；JVM堆也按总预算调整。不能把双节点多一倍资源的结果直接当作扩容效率。
3. 每轮恢复同一数据快照并完成一致的预热；保存迁移/配置代次。独立负载机优先；本机共用CPU的结果只代表该开发环境。先少量连接逐级增加，遇到持续错误/资源耗尽先保存证据，再停止该轮，不影响日常服务。
4. 在私有JSON中配置 `benchmark.mjs`，从后端根运行：

```sh
node local-dev/protocol-cluster/benchmark.mjs <private-workload.json> <new-results.json>
python3 deploy/cluster/sample-resources.py --duration 600 --interval 5 --output <new-resources.jsonl> <explicit-wearable-container-names...>
```

负载参数：`origin` 必须为隔离的 `http://127.0.0.1:<port>`，拒绝日常18084；`runId` 使用 `wearable-lab-...`，`scenario` 为 `single/dual`；`durationSeconds/reportIntervalMillis/timeoutMillis` 显式固定。`devices` 每项提供 `kind`（helmet/belt）、预登记模拟 `deviceId` 与已有 `pathToken`。每条连接只允许一个待确认心跳报文，超时断开重连，防止旧ACK被误计为下个报文成功；不会发送设备控制、SOS或媒体写入。

可用 `httpConcurrency/httpPath/sessionToken/httpSuccess` 同时施加已授权业务GET。`httpSuccess` 必须说明真实成功响应中的字段，例如 `{ "field":"revision", "type":"number" }`；按实际接口响应调整，不能只看HTTP200。凭据仅在私有文件中，结果不复制凭据。指标含尝试/成功/失败、错误率、吞吐、延迟分位数、连接峰值、重连与负载机RSS。延迟包含已完成的失败尝试；超过100万延迟样本会明确标记分位样本截断，应缩短该轮或另用直方图分析。

5. 同时按已授权的只读数据库监控账号采集锁等待、活动事务、连接池等待和慢查询；记录采集间隔/缺样。DM8与MySQL指标口径要说明，不能用一份客户端延迟报告代替数据库锁等待。`sample-resources.py` 只采容器资源，不冒充数据库监控。随附 `DatabaseMetrics.java` 仅执行固定SELECT，以JDK17和已固定的匹配JDBC驱动运行：`java -cp <jdbc.jar> deploy/cluster/DatabaseMetrics.java 600 1000 > <new-db-metrics.jsonl>`。凭据由 `METRICS_DB_PRODUCT/URL/USERNAME/PASSWORD` 环境变量提供，另须 `METRICS_ISOLATED=true`；不在命令行填密码。监控权限由DBA分配，不扩大应用账号权限。采样失败会输出error并以退出码2结束，不填0冒充无等待。

数据库样本是整个独立实例当前等待事务数、当前最大等待毫秒与活动事务数；三项SELECT分开执行，是近似同时的瞬时状态，短于采样间隔的等待可能漏采，也不代表累计等待时间。DM8依据[事务/锁动态视图](https://eco.dameng.com/document/dm/zh-cn/pm/dm8-admin-manual-appendix2.html)，MySQL依据[data_lock_waits](https://dev.mysql.com/doc/refman/8.0/en/performance-schema-data-lock-waits-table.html)和[INNODB_TRX](https://dev.mysql.com/doc/refman/8.0/en/information-schema-innodb-trx-table.html)。工具已在隔离真实双库完成10秒只读采样，尚非高负载锁等待验收。
6. 结束后对账持久设备报文、处理状态、报警/任务次数、设备归属与文件摘要；区分“持久接收ACK”和业务处理完成。未处理积压、丢数据或假成功的轮次不可计为有效容量。
7. 保存单/双节点在同等资源及负载下的原始结果，再做稳定运行和故障重连的持续测试；记录实际时长，不把短跑写成持续负载通过。对比报告必须列环境、资源、数据规模、并发连接、报文/HTTP速率、p50/p95/p99、错误率、锁等待、资源峰值与业务对账。

目前驱动只完成自身契约测试；完整Spring双节点的容量比较、数据库监控与持续负载仍待执行。
