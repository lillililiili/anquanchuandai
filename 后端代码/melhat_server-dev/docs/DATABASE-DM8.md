# MySQL / DM8 database contract

The application supports MySQL 8 and the commissioned DM8 configuration. Java 8 source compatibility and the existing Spring versions are retained. The reproducible Maven driver is `com.dameng:DmJdbcDriver8:8.1.4.93`; the driver class is `dm.jdbc.driver.DmDriver`. H2 is only a test compatibility engine and does not constitute DM8 acceptance.

## Runtime and startup

Enable `dev,mysql` or `dev,dm8` with the database profile last. `application-dm8.yml` obtains URL/user/password exclusively from `MELHAT_DB_URL`, `MELHAT_DB_USERNAME`, `MELHAT_DB_PASSWORD`; it explicitly selects DM driver, `SELECT 1 FROM DUAL`, PageHelper `dm` and DM schema resources. Database product/configuration mismatches and unknown products fail before repositories initialize.

DM8 requires `COMPATIBLE_MODE=4`, `MY_STRICT_TABLES` bits 1/2/4 all enabled (7), `CASE_SENSITIVE=0`, UTF8. `DatabaseRuntimeContract` reads the effective parameters and rejects incompatible settings during migrate/validate. The application user requires `SELECT ON SYS.V$DM_INI` in addition to its ordinary schema/DML permissions. `SF_GET_CASE_SENSITIVE_FLAG()` and `SF_GET_UNICODE_FLAG()` are read without admin credentials. An older 2024 DM8 release supporting only strict value 1 is intentionally rejected: invalid numeric input could silently become zero.

DM8 application startup only validates. Cluster startup also requires `melhat.database.schema-mode=validate`. Validation checks each version/checksum/completion marker and required table existence, and never bootstraps tracking tables or applies DDL. Schema drift fails explicitly. The default historical MySQL single-instance constructor path remains `legacy`: it centrally applies missing additive business migrations, records their steps/checksums, then validates. It does not automatically provision base RuoYi tables, import original SQL data, or repair a previously tracked table that was deleted. The default mode exists for existing entrypoints/tests; production clustered deployments must use dedicated pre-start migration.

## Dedicated migration

`com.ruoyi.database.SchemaMigration` is a standalone main; it starts no web server, repository, scheduler or device worker. Set `MELHAT_DB_PRODUCT=mysql|dm8` and the three `MELHAT_DB_*` connection environment variables above. Never supply passwords on the command line. After packaging the Boot jar, launch its dedicated main through Boot's `PropertiesLauncher`:

```text
java -Dloader.main=com.ruoyi.database.SchemaMigration -cp ruoyi-admin/target/fdc-admin.jar org.springframework.boot.loader.PropertiesLauncher
```

Only one migrator may run. The ordered resources are `db/{mysql,dm8}/00000000_base.sql`, the five historical business versions, and the separately owned shared-file migration `20261103_shared_files.sql`. The base version contains 42 schema-only RuoYi/business/Quartz tables; no original data, demo seed, account or credential is imported. Existing business import behavior remains governed by the original stores and is not a whole-database migration tool.

Resource line endings are normalized to LF before checksum calculation, so Windows/Kylin builds of the same immutable SQL have the same digest.

The tracking tables are `wearable_schema_history` (version/checksum/state), `wearable_schema_step` (step/checksum/state) and `wearable_schema_lock` (explicit migrator ownership). A step is marked STARTED before execution and COMPLETE only after execution returns. COMPLETE version status is written only after every step succeeds. Migration within an ambient business transaction is rejected, since DM/MySQL DDL can autocommit.

A failed or interrupted migration is not automatically resumed and is never marked complete. DDL can already have committed even when the last step is STARTED; inspect the recorded step and actual database state. Stop writers, retain a backup, and restore the pre-migration backup or have the database operator reconcile the exact failed version and execute/verify every remaining statement before retrying. A crashed migrator's lock requires operator verification before clearing. Do not delete production history or change checksums just to bypass validation. No automatic repair/adoption of a pre-existing DM8 schema is implemented in this phase.

## SQL and transaction behavior

`DatabaseDialect` supplies closed product detection, validated SQL identifiers, parameterized MySQL upsert / DM MERGE, insert-if-absent, pagination, metadata lookup and database time. It does not rewrite arbitrary SQL. DM unique error -6602 is the only additional vendor constraint code treated as a duplicate; all other integrity failures propagate. Business JSON reads explicitly extract CLOB text.

Business revisions, `SELECT ... FOR UPDATE` order, unique receipt identities, alarm counter allocation/committed cursors and outbox lease tokens retain their original transaction boundaries. A transient MySQL claim deadlock retries the entire short claim transaction at most three times; no network work occurs within this retry. Stale lease tokens cannot acknowledge renewed leases.

System/Quartz mappers select DM date/pagination branches using MyBatis databaseId, and use portable COALESCE, current timestamp and exact comma-delimited ancestor predicates. Code generation services explicitly reject DM8 because their introspection queries/templates remain MySQL-specific. This does not disable business services. The separate `portal-demo` database and legacy `WearableBusinessImport/Export` command-line connection setup remain MySQL-specific; whole-data cross-engine conversion/reconciliation is deferred to its separate authorized task.

## Verification

The same `RealDatabaseContract` runs against independent environment-provided `DM8_CONNECTION_FILE` / `MYSQL_CONNECTION_FILE` JSON files containing `jdbcUrl`, `username`, `password`. No credentials are stored in test sources or passed on CLI arguments. Resetting schemas additionally requires the explicit `DM8_RESET_TEST_SCHEMA=true` / `MYSQL_RESET_TEST_SCHEMA=true` switch; the guard only permits DM user `WEARABLE_TEST` or MySQL user/database `wearable_test`. These flags are only for disposable isolated schemas.

The contract verifies complete clean schema installation/checksum validation, identity keys, system date/ancestor filters, Quartz mutation, 70,000-character CLOB snapshots, revisions and rollback, duplicate receipt checks, device journal pagination, booleans/time, helmet replay deduplication, maintenance mode, late alarm ordering, uncommitted alarm cursor visibility, competing push claims and stale-token rejection. Unit/contract tests also cover unknown products, identifier injection, checksum drift, failed DDL recording, validate-only startup and ambient transaction rejection.

Confirmed real targets: MySQL 8.0.46; DM8 official 20260817 distribution engine `03134284604-20260707-335949-20228` with strict flags 7, using Maven driver 8.1.4.93. The distribution also ships driver 8.1.5.60 (SHA256 `a003c3c803c06d32f5a59285fcd5ac0e3f0fb4fd35dd24ef0179bc44d2aec10f`); that bundled jar was inspected by the runtime owner and is not claimed as the tested Maven driver.

Windows tests require an ASCII temp directory in this environment:

```text
mvn -B -pl ruoyi-admin -am "-DargLine=-Djdk.net.unixdomain.tmpdir=D:/DevTools/dm8-tmp -Djava.io.tmpdir=D:/DevTools/dm8-tmp" test
```

The older opt-in `FudaPushMySqlTest` retains its dedicated `fuda.push.mysqlTestPort` switch and `fuda_push_test` schema, but now requires `FUDA_MYSQL_TEST_USERNAME` / `FUDA_MYSQL_TEST_PASSWORD` environment variables. Its fixture resets the matching migration tracking rows when it deliberately drops the outbox table. It is independent of the new shared real-database contract.

This database acceptance does not establish full application startup, clustered session correctness, whole-data migration or Kylin deployment acceptance. Those are separate integration/deployment tasks.
