# S9 作业任务与值班台契约

版本：S9　依赖：[00-common.md](00-common.md)、[s1-auth.md](s1-auth.md)、[s2-people.md](s2-people.md)、[s4-assignment.md](s4-assignment.md)、[s5-events.md](s5-events.md)

最小作业任务不是工作票。无票且要求票号时显示「待核实」，**不是违章**。任务结束 **不**关闭事件。多任务命中同一事件时 `taskMatch=pending`，不得任意选一个。安全带无真实遥测时装备检查为 `unknown`，不得标正常。厂站与 `X-Site-Id` 同 S1。隐藏按钮 ≠ 已授权。`demo: true` 不得当生产作业。

## 1 任务状态

`draft` → `ready` → `in_progress` ⇄ `paused` → `ended`

有成员且有计划起止时间后可 `ready`。`start` 进入进行中。结束可从 `in_progress` / `paused` / `ready`。存在未关闭高风险关联事件时，结束须 `acknowledgeOpenHighRisk=true`，事件保持原状。

## 2 权限

| 能力 | 角色 |
| --- | --- |
| 查询任务、装备检查、值班摘要、交接列表 | 值班、班组长、复核、只读、设备管理员、平台（授权厂站） |
| 建改任务、成员、start/pause/end、确认事件任务、发起/确认交接 | 值班、班组长 |

只读/复核/平台写 403。权限字：`wear:task:list` `wear:task:query` `wear:task:edit` `wear:duty:query` `wear:duty:handover`。

## 3 接口

`GET /api/v1/work-tasks` 分页。`POST /api/v1/work-tasks` 创建。  
`GET /api/v1/work-tasks/{id}` 含成员、要求、装备检查、关联事件。  
`PUT /api/v1/work-tasks/{id}` 带 `version`。  
`POST /api/v1/work-tasks/{id}/members` `{ "personIds": ["1"] }`  
`DELETE /api/v1/work-tasks/{id}/members/{personId}` 已结束 409。  
`POST .../start` `.../pause` `.../end`（end 可带 `acknowledgeOpenHighRisk`）。  
`GET /api/v1/work-tasks/mine`  
`GET /api/v1/work-tasks/{id}/equipment-check`  
`GET /api/v1/work-tasks/{id}/events`  
`POST /api/v1/events/{id}/task` `{ "taskId": "1", "version": 1 }`，`taskId` 空表示不关联。

`GET /api/v1/duty/summary` 仅当前厂站：`unclaimed` `mine` `overdue` `lostSupervision` `peopleCount` `deviceCount` `activeTasks` `recentEvents`。  
`GET/POST /api/v1/duty/handovers`；`POST /api/v1/duty/handovers/{id}/confirm`。未确认不改责任。

装备检查项：`personId, typeCode, result`（`missing` | `ok` | `unknown`），可附 `needsConfirm`。人数与设备数分开统计。

事件：`taskId`、`taskMatch`（`none` | `matched` | `pending`）。

## 4 错误

| 场景 | HTTP | msg 方向 |
| --- | --- | --- |
| 未登录 | 401 | 未登录或登录已过期 |
| 只读写、跨站 | 403 | 没有权限执行该操作 |
| 状态/版本冲突、已结束改成员 | 409 | 当前状态冲突，请刷新后重试 |
| 高风险未关闭且未确认结束 | 409 | 存在未关闭的高风险事件，确认后才能结束任务 |
| 人员不可选 | 400 | 该人员当前不可加入任务 |

## 5 值班接管与明细（2026-09-21）

按每厂站一名当前值班负责人记录。旧权限表中的交接部分由本节替代，其他作业权限不变。

- `GET /api/v1/duty/operators` 包含有效的内置 admin（用户 1），无需额外值班角色或厂站成员配置；停用/删除账号不参与。其他接班人仍校验厂站授权及值班、班组长或平台管理员资格。安卓排除发起人自己。
- 发起交接仅允许当前值班负责人；尚无值班记录时允许有交接资格的用户发起初始交接。同厂站当前值班人已有 pending 时返回 409，需完成或取消；发起本身不改变负责人或时长。
- `POST /api/v1/duty/handovers/{id}/cancel`：`{reason}`，管理员或原发起人可取消 pending；其他人 403，已处理记录 409。取消不改变值班人与事件/任务责任，记录保留为 cancelled。原因 1–200 字。
- `POST /api/v1/duty/takeover`：`{expectedShiftId,reason}`，仅管理员（内置 admin 或平台管理员）可将所选厂站当前值班转为自己。必须提交页面读取的当前班次 ID；尚无班次时为 null；过期快照/已经当班为 409。无须原值班人确认。
- 正常确认及接管在同一事务中结束旧班次、创建新班次，并转移仍属于原负责人和该厂站的未关闭事件、未结束任务；事件状态不变（包括待复核）。管理员接管取消该厂站遗留待接班交接并记录原因。旧责任已经转给他人的，不覆盖。
- `GET /api/v1/duty/shifts?current=1&size=20`：返回 `records,total,currentDuty,serverTime,canTakeover`。记录包含 `id,userId,userName,startedAt,endedAt,durationSeconds,changeType,reason,handoverId,endUnknown`。`endedAt=null` 通常表示至今；`endUnknown=true` 表示历史结束时间缺失，时长为 null，不表示仍当班。
- 交接 DTO 新增 `canCancel` 和 `audit`（`action,actorName,actedAt,reason`）。管理员操作、取消原因持续可查询。值班明细分页，不限于原交接列表最近 20 条。
- `wear_duty_station` 行锁串行化同厂站确认、取消、接管；条件更新防止重复确认或取消。前端再次确认接管并填写原因，不提前展示成功。

数据库按序执行 V013、V014。V013 从历史确认记录建立标为 `legacy_confirmation` 的班次；V014 将交接链不连续的旧记录标为 `legacy_incomplete`，结束时间/完整时长未知。迁移不补造旧交班人的开始时间，也不修改原交接记录。
