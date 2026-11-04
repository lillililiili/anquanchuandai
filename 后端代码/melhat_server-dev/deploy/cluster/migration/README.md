# 数据迁移、备份、还原与对账

`migrate.py` 使用 **同一个已验证后端 jar** 中的 SchemaLifecycle、双库 SQL 资源和 JDBC 依赖，独立运行 JDBC 工具，不启动 Web、设备控制、定时任务或外部推送。支持 MySQL→DM8，也支持 DM8→空 MySQL 库。正式切换仍需完成完整业务、目标麒麟主机和真实设备验收。

## 前提与私有配置

需要 JDK 17、Python 3.9+、Docker CLI，以及两个已通过专用 `SchemaMigration` 建表/校验的独立库。达梦应用账号需要本模式的读写/建表权限以及 `SELECT ON V$DM_INI`，用于验证严格参数；本机已用 RESOURCE 加该项查询权限初始化，无需为应用账号授予 DBA。迁移期间保留停止的应用容器，不能先删除其配置证据。新目标可先 `docker compose create app-a app-b`，保持从未启动状态。

工作目录、导出包父目录、journal/report 父目录在 Linux 上必须归当前账号所有、权限0700；工具使用私有 umask。Windows 开发环境需显式限制这些目录 ACL。导出含业务原文、设备信息及私有配置备份，不能放进公开交付包、Git、共享下载目录或公开日志。

在私有文件中填写端点配置。下面只有格式示例，尖括号值须由操作者填写：

```json
{
  "product": "dm8",
  "url": "jdbc:dm://127.0.0.1:15237",
  "schema": "<APPLICATION_SCHEMA>",
  "username": "<APPLICATION_SCHEMA>",
  "password": "<private>",
  "databaseContainerId": "<完整64位Docker数据库容器ID>",
  "targetId": "<为该目标配置登记的UUID>",
  "sharedRoot": "/mnt/wearable",
  "backendEnvFile": "/private/target/backend.env",
  "configurationFiles": [
    "/private/target/gateway-input.json",
    "/private/target/gateway-manifest.json",
    "/private/target/helmet-a.json",
    "/private/target/helmet-b.json",
    "/private/target/belt-a.json",
    "/private/target/belt-b.json",
    "/private/target/Caddy.devices"
  ],
  "urlMappings": [{"prefix": "/profile/", "directory": "upload"}],
  "externalMediaPrefixes": []
}
```

MySQL 使用 `product=mysql`，URL 中明确数据库名，schema 填数据库名。`backendEnvFile` 必须包含对应数据库设置、JWT_SECRET、MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY。两端保留相同 JWT/媒体密钥和共享文件 store UUID；不要把原数据库地址一并照搬到新环境。`configurationFiles` 应完整列出实际入口、设备凭据、节点和运维配置，源文件按编号原样备份，不会在输出中显示内容。独立媒体服务的存储另行备份，不在共享目录时不会自动包含。

工具核对实际数据库容器 ID、JDBC 映射端口/网络别名/schema、停止容器的网络与数据库配置、JWT/媒体密钥。只有相同用户名或 node-id 不足以证明停机。当前这层自动核验面向同一 Docker 主机的部署；外置裸机数据库、跨主机部署不能伪填容器证据，需先接入实际环境的停写证明与验收流程。

## 导出与离线对账

1. 停止设备新接入，暂停全局写入，等待 active operations、媒体操作、福大推送和设备发送过程结束。未确认的外部操作要先查证；不能把过期许可视为已完成。已明确记录的终态 `UNKNOWN` 设备指令可以保留在备份中，恢复时不会重新排队。尚在 PREPARING/QUEUED/DISPATCHING/SENT 的传输命令必须先结束或取消。
2. 排空、停止所有应用节点，保留容器；等待数据库中的节点租约失效。工具核对数据库里登记的每个节点均包含在停止清单内，并要求 `global=PAUSED`、没有在途操作。不要在导出/导入期间重新启动任何节点或直接改文件。
3. 使用一个全新包目录：

```sh
python3 deploy/cluster/migration/migrate.py export \
  --application-jar /private/release/fdc-admin.jar --config /private/source.json \
  --bundle /private/backups/final-001 --work-dir /private/work \
  --offline-app <source-app-a-container> --offline-app <source-app-b-container>
```

快照期间 MySQL 对相关表持 READ 锁，DM8 对相关表持 SHARE 锁；失败不会退化成无锁导出。文件逐项复制、摘要核验并再次回读原目录，文件指针、照片关联和已配置的本地 URL 关联必须能解析。任何 symlink、路径穿越、缺失/损坏文件或未映射文件地址都会阻止完成。

完成包包含 `manifest.json`、manifest.sha256、tables/*.jsonl、files/ 和 configuration/。只有 `state=COMPLETE` 且所有摘要有效的包可导入。表清单来自同一 jar 的迁移资源；缺表或额外有数据的未知表拒绝导出。schema history/step/lock 不跨产品复制；节点、设备连接归属、工作许可等易失表仅归档，恢复端保持空，设备通过重连产生新归属。

行包含类型化值和主键，按规范化文本进行分段排序，再以最多64路归并生成稳定摘要。JSON 对象字段顺序、十进制格式不影响语义比较；字符串/CLOB、二进制、日期及时间分别处理。媒体密文先用原密钥验证认证和 JSON 内容，再保留原密文，不重新加密。DM8 的 JSON 列可能由 JDBC 报为 BLOB，工具以 UTF-8 文本读入并使用文本 JSON 参数写入，普通二进制仍按原字节处理。

当前安全边界为单文本单元最多16 Mi字符、单二进制单元16 MiB、单行规范化文本32 Mi字符；超限明确报错，不截断、不生成完成包。大于这些边界的数据须先评估并扩展流式单元格式，不能把失败当成“无数据”。

## 导入、恢复与复核

目标须是相同 jar 已迁移出的空业务库，且共享目录只保留相同 `files/.wearable-store-id`。迁移自带的两个控制种子行允许存在；任何业务行都不能被覆盖。工具在写入前校验全部表/文件/配置摘要、密文认证、类型和应用 jar 摘要。

```sh
python3 deploy/cluster/migration/migrate.py import \
  --application-jar /private/release/fdc-admin.jar --config /private/target.json \
  --bundle /private/backups/final-001 --work-dir /private/work \
  --offline-app <target-app-a-container> --offline-app <target-app-b-container> \
  --confirm-target <targetId> --journal /private/journals/import-001.json

python3 deploy/cluster/migration/migrate.py reconcile \
  --application-jar /private/release/fdc-admin.jar --config /private/target.json \
  --bundle /private/backups/final-001 --work-dir /private/work \
  --offline-app <target-app-a-container> --offline-app <target-app-b-container> \
  --report /private/reports/reconciliation-001.json
```

导入按外键依赖排序，不普遍禁用约束。行数据在一个事务中导入，文件在提交前按新路径发布；事务失败时文件可能留下，但不会返回成功。所有权、行提交、自增属性 DDL 和最终对账分别记录在 journal。应用启动会因 schema owner 非空而拒绝进入服务，直到迁移完成；不要手工清 owner 来绕过检查。

DM8 的自增水位需保留已删除 ID：工具记录原水位，以 `DROP IDENTITY` 移除**属性**，再对同一个 NOT NULL 列恢复 IDENTITY(seed,1)。不会删除列或业务表。DDL 可能自动提交，因此不能把它描述为整批事务回滚。journal 使用排他文件锁；每次 resume 先核对端点、包与 owner，再通过数据库 CAS 获得新的执行所有权。始终使用原 journal，不能复制一个新 journal 绕开运行中的操作。

只有 ROWS_COMMITTED、RESEEDING、RESEED_FAILED 可用同一命令参数把 `import` 改成 `resume`。恢复先对完整行/文件回读，水位只提高不降低，再执行缺失的自增属性步骤。ROWS_FAILED_OR_COMMIT_UNCERTAIN、journal 写入异常或所有权不符时禁止自动重放：保留目标、包和 journal，先核实提交状态。对可丢弃目标，重新准备独立空库和空共享目录最清楚；对有价值目标，应根据 journal 逐项核对，不执行无条件清库。

独立 `reconcile` 会检查全部恢复表的行数、包含主键的规范化摘要、自增水位和文件摘要；同条数但内容不同会失败。JSON journal/report 保存每表实测行数、摘要、主键列和实际 nextIdentity，只有全部通过才写 COMPLETE。未指定 report 时，在包旁生成新的唯一报告文件，不覆盖旧报告。

## 切换与回滚

正式顺序：暂停旧端写入 → 最终导出并核验 → 空新库导入/对账 → 单节点验证登录、权限、设备、定位、报警、照片及必要媒体 → 加入第二节点并验证跨节点操作 → 切换入口 → 恢复写入。配置快照、数据库包、文件及密钥必须作为同一恢复点保留；入口、数据库、Redis、NAS 自身冗余仍另行建设。

新端**尚未产生业务写入**时，可停止新端，确认旧端仍在原冻结点后把入口切回，并按已验证流程恢复旧端写入。

新端**已经产生业务写入**时，先重新暂停/排空新端，完整导出新库与文件并对账。可在新的空 MySQL 目标还原这份最新数据，再以同版本、已验证的 MySQL 应用配置做单节点和业务验收后切回；也可按专门审查过的增量方案迁回。禁止直接恢复旧备份或让旧端继续写入而丢掉新端新增记录。回退旧代码版本另需验证数据库/数据格式兼容性。

## 当前证据与边界

最终完整JAR SHA256 `35290a865fe8169bdaeeacab57151e379b7235a2808a4e7cbf0e8358158e8614` 已在本机隔离真实MySQL8/严格DM8完成双向往返：两份包各99表、28行、4文件，三次对账均COMPLETE，验证91张恢复表27行、内容、自增水位及文件，其余8张运行态表仅归档。两端新增记录的自增键和恢复审计JSON另行读回通过。证据见仓库 `.superpowers/sdd/report-migration-release-final.md`。

真实进程kill、自增属性删除后恢复、并发/旧owner拒绝、9e12高水位、零主键、同条数篡改、坏文件、非法JSON及非空目标矩阵曾在71ab732e完整JAR上通过；本次未在35290a86重跑。递归字节比较确认相关迁移类、SQL和JDBC没有改变；这个比较和新构建往返验证各自记录，不将旧故障矩阵冒称为新构建运行结果。

另已从实际四模拟设备应用，在暂停和排空后用最终JAR导出99表、12246行、5文件的容量基线，并通过源库离线对账；容量目标的恢复和测量另行记录。这些仍是开发数据与本机容器验证，不能代替真实数据量、麒麟、NAS/NFS和设备切换验收。

测试期间原1.5GB DM8容器曾OOM退出，已保留未完成DDL记录而没有补写成功；恢复后先调整为2GB，最终往返和当前容量准备固定为3GB/1CPU。受影响模式留作证据，故障矩阵使用新的模式。正常重启释放缓存前先停止全部应用并保留完整快照；没有清库或删除业务记录。此事件不涉及日常数据库，也不构成容量结果。

SQL依据：[达梦事务表锁](https://eco.dameng.com/document/dm/zh-cn/pm/management-affairs.html)、[MySQL表锁](https://dev.mysql.com/doc/refman/8.4/en/lock-tables.html)、[达梦现有列自增属性](https://eco.dameng.com/document/dm/zh-cn/pm/definition-statement.html)、[达梦自增水位函数](https://eco.dameng.com/document/dm/zh-cn/pm/sql-appendix.html)、[达梦JSON](https://eco.dameng.com/document/dm/zh-cn/pm/json)。实际SQL和恢复行为以固定版本的真实数据库测试为准。
