# S10 位置与围栏契约

版本：S10　依赖：[00-common.md](00-common.md)、[s1-auth.md](s1-auth.md)、[s3-devices.md](s3-devices.md)、[s4-assignment.md](s4-assignment.md)、[s5-events.md](s5-events.md)、[s6-helmet.md](s6-helmet.md)

主位置与轨迹只用来自 **安全帽 GNSS 样本**。安全带不打点。楼层未知不编造。`locationQuality` 非 `ok` 或点已陈旧 **不得**产生越界事件。禁用围栏不删除历史。坐标系 WGS84。厂站与 `X-Site-Id` 同 S1。隐藏按钮 ≠ 已授权。`demo: true` 不得当生产在线。旧 `/hat/electronic/fence` 不是本契约真相。

## 1 人员位置

一个人一个主位置：当前有效领用安全帽的最近有坐标样本。无帽/无点：人仍返回，坐标空，`locationQuality=unknown`。`floor` 恒为 `null`，`floorSource=unknown`。

`GET /api/v1/locations/people` 分页。  
`GET /api/v1/locations/people/{id}`  
`GET /api/v1/locations/people/{id}/tracks?from&to&current&size` 上限 500，超出抽稀。跨站 403。空列表 200。

## 2 围栏

多边形 ≥3 点。`applyMode`：`all_site` | `persons`。可选每日 `timeStart`/`timeEnd`（`HH:mm`）。`debounceSeconds` 默认 60（实验室种子可为 0）。改几何或进出规则升 `ruleVersion`。

`GET/POST /api/v1/fences`  
`GET/PUT /api/v1/fences/{id}` 带 `version`  
`PUT /api/v1/fences/{id}/enabled`  
`POST /api/v1/fences/evaluate` 仅非 prod + demo-mode。

判定仅 `ok` 且未陈旧的点。进出驻留满防抖后写入事件 `type=geofence` `source=geofence`，带 `fenceId` `fenceAction`（`enter`/`leave`）`ruleVersion`。

## 3 权限

| 能力 | 角色 |
| --- | --- |
| 位置、轨迹、围栏查询 | 值班、班组长、复核、只读、设备管理员、平台 |
| 围栏写入 | 设备管理员、平台、若依 admin |

权限字：`wear:location:list` `wear:location:query` `wear:fence:list` `wear:fence:query` `wear:fence:edit`。值班写围栏 403。

## 4 错误

| 场景 | HTTP | msg 方向 |
| --- | --- | --- |
| 未登录 | 401 | 未登录或登录已过期 |
| 跨站、只读写围栏 | 403 | 没有权限执行该操作 |
| 多边形非法、缺 version | 400 | 服务端 msg |
| 版本冲突 | 409 | 当前状态冲突，请刷新后重试 |
