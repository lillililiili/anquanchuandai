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
