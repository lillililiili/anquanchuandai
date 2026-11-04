# 定位与告警 IDENTITY 映射修正

## 结论

真实DM8专用WEARABLE_TEST库复现了父完整应用定位积压的根因：MyBatis-Plus未声明AUTO的实体产生含id的INSERT，DM8 IDENTITY列拒绝显式赋值。`DirectHelmetPersistence.receive`同一流程的三条分支均已真实复现，不能只修定位而漏掉告警/SOS。

仅修改 `SafetyHatLocationRecord.id`、`RealTimeAlarm.id`、`SosAlarmRecord.id` 三处映射为 `@TableId(type = IdType.AUTO)`（及imports）；既有 SafetyHatInfo AUTO 保留。没有修改数据库DDL、既有migration checksum、全局id-type、接收ACK语义或处理状态逻辑。已有ID/关联行不重写，新记录由数据库生成ID并回填，告警link引用回填ID。

父故障日志 `output/dm8-cluster/private/acceptance-valid-1104/app-a-pending.log` 的DataIntegrityViolationException由本轮真实vendor异常证据补全。父应用库、原始积压、容器均未操作；新包恢复父应用的425帽报文和326安全带报文仍由父实际启动读回，不把本轮单JVM专用测试当容量/跨节点验收，也未证明安全带积压必然同根因。

## RED与根因证据

`output/dm8-cluster/location-identity-dm8-red.log`：3 tests / 3 errors，定位、ca_sos、ca_sip_sos分别失败。三次均先通过真实 `WearableReportDelivery.helmet` 持久写入原始接收记录；暂停模式下返回false表示尚未处理，不代表未接收。恢复处理走真实delivery→processReport事务→TelemetryService→DirectHelmetPersistence→MyBatis mapper。

三条异常均为DM JDBC `DMException`，vendor code **-2723**，SQLState **22000**，说明显式向自增列赋值需要IDENTITY_INSERT；这不是连接不可用或读取性能问题。定位异常实际SQL：

```sql
INSERT INTO safety_hat_location_record
(id, lng, hat_number, del_flag, hat_id, create_by, create_time, lat, timestamp)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
```

同一日志另有real_time_alarm和sos_alarm_record的含id INSERT与相同vendor错误。仓库既有DM8 base SQL三个表均是`id bigint IDENTITY(1,1) NOT NULL`；未改DDL。测试在异常后断言原始receipt仍存在且processed_at NULL，目标业务表0行，避免把接收成功误判成处理完成。

## GREEN与真实回执恢复

- `location-identity-dm8-green.log`：最初3条分支全部通过，PID64940，真实生成ID、业务journal/Guardian投影、processed标记同链完成，重复delivery不增行。
- `location-identity-dm8-recovery.log`：最终5 tests / 0 failures / 0 errors / 0 skips，PID60600，2026-11-04T02:00:47-05:00。真实恢复上一轮vendor失败留下的同3条receipt，没有删除或重新接收：
  - 定位 `WR-424ab346-eed5-4b27-855f-52ef4685a225`。
  - SOS原始表 `WR-160c965c-7c2e-4e7a-86c4-932031c3776a`。
  - 实时告警 `WR-d8b5c253-7a1c-4fc9-b613-c9027ba715ef`。
  - 各自processed=true，业务表1行，定位journal或event link/projected均1行；第二次deliver仍1行。
- 可重复故障测试在真实业务SQL与journal插入后注入异常，确认这些SQL回滚，原始receipt保持pending；随后用同receipt恢复并重复投递。DM receipt `WR-026896fd-7c13-42a1-8bcb-535125281fde`，最终定位ID5，一行；IDENTITY被回滚事务消耗的值不强行复用。
- `location-identity-mysql-green.log`：真实MySQL同5条用例+相邻19条，共24 tests / 0 failures / 0 errors / 0 skips，PID61508，2026-11-04T02:01:25-05:00。MySQL无先前vendor失败积压（recovered=0，明确不算旧DM失败证据），但可重复SQL异常后同receipt恢复已实测，receipt `WR-0a9e93c9-051f-4814-8cb6-7e08691d945f`，最终ID3一行。
- 相邻定向回归：DirectHelmetIngestTest12、WearableReportDeliveryTest2、DirectHelmetTelemetryTest4、DirectHelmetTransactionTest1。

新增 `RealDirectHelmetIdentityTest` 使用真实SingleConnectionDataSource、MyBatisSqlSessionFactory/SqlSessionTemplate、4个真实mapper、GuardianHatArchive/Store/Ingest、HelmetBusinessJournal、WearableBusinessStore及delivery/telemetry/persistence；只有维护暂停门槛为测试控制，后置异常为fixture故障注入。没有mock mapper或H2冒充vendor证据。业务事务由真实processReport开启，同DataSource加入；测试不启动Spring全容器、网关或Redis。仅允许WEARABLE_TEST:15237 / wearable_test:15306；SchemaLifecycle validate-only，无DDL。临时Guardian设备投影测试后恢复原快照，合成原始回执与SQL结果保留供审计；没有清理父业务数据。

## 复现命令

在 `后端代码/melhat_server-dev`：JAVA_HOME=`D:/DevTools/jdk-17.0.20.1+1`，Maven=`D:/DevTools/apache-maven-3.9.16/bin/mvn.cmd`；MAVEN_OPTS=`-Xmx384m`。LOCATION_CONNECTION_FILE指向 `W/output/dm8-cluster/private/dm8-20260817-connection.json` 或 `mysql-connection.json`，内容不打印。

```powershell
mvn.cmd -B -pl ruoyi-admin -am '-Dtest=RealDirectHelmetIdentityTest' '-Dsurefire.failIfNoSpecifiedTests=false' '-DargLine=-Xmx512m -Dfile.encoding=UTF-8 -Djdk.net.unixdomain.tmpdir=D:/DevTools/dm8-tmp -Djava.io.tmpdir=D:/DevTools/dm8-tmp' test
```

MySQL最后一轮`-Dtest`值为`RealDirectHelmetIdentityTest,DirectHelmetTelemetryTest,DirectHelmetTransactionTest,DirectHelmetIngestTest,WearableReportDeliveryTest`。RED命令同单类测试，仅当时实现未加AUTO、未加后续恢复两例，且没有file.encoding参数；原log中文编码显示可能不一致，SQLState/vendor代码/SQL列及断言完整。

## 最终包与内容核对

第一次普通package `location-identity-package.log` 虽BUILD SUCCESS，但仅system模块变更时，旧Spring Boot repackage保留了up-to-date外层旧fatjar；hash核对发现仍ccafb8f0，复制旧只读副本被拒，没有覆盖旧证据。此包没有当修复包交付。

改用强制重建jar；首次未给PowerShell的点号参数加引号，Maven解析失败记录在`location-identity-package-final.log`。正确命令如下，`location-identity-package-final2.log` BUILD SUCCESS（2026-11-04T02:03:27-05:00）：

```powershell
$env:MAVEN_OPTS='-Xmx512m -Djdk.net.unixdomain.tmpdir=D:/DevTools/dm8-tmp -Djava.io.tmpdir=D:/DevTools/dm8-tmp'
mvn.cmd -B -pl ruoyi-admin -am -DskipTests '-Dmaven.jar.forceCreation=true' package
```

固定只读副本 `output/dm8-cluster/fdc-admin-final-1f0b9939.jar`，110207912 bytes；SHA256 **1F0B99397B343EC750B754C1DE3B38A13E88F5EE96B300E91DCB2F654D59063D**。原target/fdc-admin.jar同hash。

`location-identity-artifact-comparison.json` 记录与旧ccafb8f0逐字节对比：25个migration SQL文件集合与内容完全不变；DmJdbcDriver8-8.1.4.93、mysql-connector-java-8.0.29、Spring JDBC两依赖均不变；嵌入ruoyi-system仅上述3个实体class变化，并逐字节匹配真实测试已执行的target/classes。没有修改POM、SchemaLifecycle或驱动，不需要重建/重导业务库。

## 代码变更说明

|文件/类|方法/字段|作用|本次修改|
|---|---|---|---|
|SafetyHatLocationRecord|id映射，无新增方法|定位记录主键|声明AUTO，新增定位由数据库生成ID|
|RealTimeAlarm|id映射，无新增方法|实时告警主键|声明AUTO，event link使用数据库回填ID|
|SosAlarmRecord|id映射，无新增方法|SOS记录主键|声明AUTO，event link使用数据库回填ID|
|RealDirectHelmetIdentityTest|setup/restore/verifyReport、5测试|真实vendor接收与SQL事务/投影验证|覆盖三分支、保留失败receipt、同receipt恢复、重放不重复、坐标与生成ID读回|
