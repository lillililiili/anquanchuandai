# 数据库迁移约定（S0-04）

本目录存放 **增量结构变更**。S1：`V001__site_and_account_grant.sql`。S2：`V002__person_org_space.sql`。S3：`V003__device_and_model.sql`。S4：`V004__assignment_and_lifecycle.sql`。S5：`V005__safety_event.sql`。S6：`V006__helmet_ingest.sql`。S7：`V007__call_and_command.sql`。S9：`V008__work_task_and_duty.sql`。S10：`V009__location_and_fence.sql`。导航整理：`V010__menu_nav_cleanup.sql`。

## 编号

```text
V001__short_description.sql
V002__short_description.sql
```

- 前缀 `V` + 三位序号，双下划线，英文或拼音描述。
- 序号全局递增，禁止改已经发布过的脚本内容。需要修正时新增更高序号。
- 一个脚本只做一件事（一张表或一组紧密约束）。

## 与现有 SQL 的关系

| 文件 | 职责 | 是否当迁移 |
| --- | --- | --- |
| `sql/ry_20230223.sql` | 若依基线库（用户、角色、菜单等） | 否，空库初始化用 |
| `sql/quartz.sql` | 定时任务表 | 否，空库初始化用 |
| `sql/melhat_demo.sql` | 帽子业务表 + 可识别演示数据（`create_by='demo'`、`MH-DEMO-*`） | 否。**不是**生产迁移完成，也不是通用 Device/Person 模型 |
| `sql/migrations/Vxxx__*.sql` | 自 S1 起的结构变化 | 是 |

新模块的所有表、列、索引、约束必须进入本目录。禁止只在测试库手工 `ALTER` 而不留脚本。

## 执行

S0 未引入 Flyway/Liquibase。联调库由维护者按序号手工执行，并在交接单记录已执行到的最大序号。S11 再把迁移纳入发布检查。

## 演示数据识别

- 演示帽子编号：`MH-DEMO-` 前缀
- 演示写入账号：`create_by = 'demo'`
- 测试库名与生产库名必须不同（本机示例：`melhat_local`）
