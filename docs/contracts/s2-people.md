# S2 人员与基础资料契约

版本：S2　依赖：[00-common.md](00-common.md)、[s1-auth.md](s1-auth.md)

人员 **独立于登录账号**。选择人员不得依赖 `/system/user/list`。厂站范围仍由服务端校验，`X-Site-Id` 规则同 S1。

## 1 可选判定（S4/S9 复用）

人员可用于 **新** 领用/新任务，当且仅当：

- `status = 0`（在职）且未删除
- 在目标厂站有有效 `wear_person_site`（未调离）
- 当前时间落在 `validFrom`–`validTo`（空表示不限制）

停用、调离、过期后历史详情仍可按稳定 ID 打开。接口字段 `selectable` 表示对 **当前厂站**（或请求中的 `siteId`）是否可选。

## 2 权限

| 能力 | 角色 |
| --- | --- |
| 人员列表/详情/选择器、区域查询 | 值班、班组长、复核、只读、设备管理员、平台管理员 |
| 人员/班组/承包商/区域写入 | 设备管理员、平台管理员、若依 admin |

权限字：`wear:person:list|query|edit`，`wear:space:list|edit`，`wear:team:edit`，`wear:contractor:edit`。

只读写入 403。隐藏按钮 ≠ 已授权。

## 3 人员接口 `/api/v1/people`

分页查询 `GET /api/v1/people?current&size&name&personCode&status&teamId&contractorId`  
范围：当前厂站；未选当前站时为授权厂站并集。跨站人员不出现。

详情 `GET /api/v1/people/{id}`：无授权厂站交集则 403。

选择器 `GET /api/v1/people/options?name=`：仅 `selectable=true`。

新增 `POST /api/v1/people`：`accountUserId` 可空。`siteIds` 必须都在账号授权内；缺省则授予当前厂站。

修改 `PUT /api/v1/people/{id}`：带 `version`，冲突 409。

状态 `PUT /api/v1/people/{id}/status`：`{ "status": "1", "version": 1 }` 停用不删历史。

人员对象：

```json
{
  "id": "1",
  "personCode": "P-DEMO-001",
  "name": "演示人员01",
  "orgDeptId": null,
  "teamId": "1",
  "teamName": "A站巡检班",
  "contractorId": null,
  "contractorName": null,
  "accountUserId": "12",
  "status": "0",
  "validFrom": null,
  "validTo": null,
  "selectable": true,
  "siteIds": ["1"],
  "version": 1
}
```

姓名允许重复；`id` / `personCode` 区分。

## 4 班组、承包商、区域

- `GET/POST /api/v1/teams`，`PUT /api/v1/teams/{id}`：班组隶属 `siteId`。
- `GET/POST /api/v1/contractors`，`PUT /api/v1/contractors/{id}`：承包商不是厂站。
- `GET /api/v1/spaces?siteId=`：区域资料列表，无实时定位。
- `POST /api/v1/spaces`，`PUT /api/v1/spaces/{id}`：`spaceType` 为 `area` | `facility` | `floor`。

单位（组织）复用若依部门 ID，S2 不提供部门维护接口。
