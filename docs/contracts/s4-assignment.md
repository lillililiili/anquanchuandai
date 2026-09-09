# S4 领用归还契约

版本：S4　依赖：[00-common.md](00-common.md)、[s2-people.md](s2-people.md)、[s3-devices.md](s3-devices.md)

领用人是 **Person**，不是登录账号。一台设备同时只有一条有效领用。一人可同时持有一顶安全帽和一条安全带。厂站与 `X-Site-Id` 同 S1。

## 1 有效领用

`returnedAt == null` 表示有效。归还不删行，只填结束时间、原因和办理账号。

领用当且仅当：

- 人员 `PersonEligibility.selectableForNewWork` 对**设备所在厂站**为 true
- 设备已分配该厂站且 `assetStatus = in_stock`
- 该设备无有效领用
- 该人员在该类型（`helmet` / `belt`）上无有效领用

否则 400 或 409，`msg` 为具体原因。

## 2 权限

| 能力 | 角色 |
| --- | --- |
| 当前装备、历史、详情 | 值班、班组长、复核、只读、设备管理员、平台管理员 |
| 领用、归还、异常回收、调拨 | 设备管理员、平台管理员、若依 admin |

权限字：`wear:assignment:list|query|issue`。只读写入 403。隐藏按钮 ≠ 已授权。

## 3 接口

领用 `POST /api/v1/assignments`  
`{ "deviceId": "1", "personId": "1", "idempotencyKey": "optional-uuid" }`

归还 `POST /api/v1/assignments/{id}/return`  
`{ "reason": "班后归还", "idempotencyKey": "..." }`

异常回收 `POST /api/v1/assignments/{id}/recover`  
`{ "reason": "设备损坏强制收回", "assetStatus": "maintenance", "idempotencyKey": "..." }`  
`assetStatus` 缺省为 `in_stock`。有效领用存在时，不能用 `PUT /devices/{id}/asset-status` 直接改维修/停用/报废（409）。

当前：`GET /api/v1/devices/{id}/assignment`（无领用时 `data: null`，HTTP 200）  
`GET /api/v1/people/{id}/equipment`  
`GET /api/v1/me/equipment`（账号未关联人员则为 `[]`）

历史：`GET /api/v1/devices/{id}/assignments`、`GET /api/v1/people/{id}/assignments`（时间倒序）

详情 `GET /api/v1/assignments/{id}`：无厂站交集 403。

相同 `idempotencyKey` 重复提交返回同一条领用，不新建。也可使用请求头 `Idempotency-Key`。

对象：

```json
{
  "id": "1",
  "deviceId": "1",
  "sn": "MH-DEMO-001",
  "typeCode": "helmet",
  "personId": "1",
  "personCode": "P-DEMO-001",
  "personName": "演示人员01",
  "siteId": "1",
  "issuedAt": "2026-09-08T12:00:00+08:00",
  "returnedAt": null,
  "issuedBy": "wear_admin",
  "returnedBy": null,
  "returnReason": null,
  "returnKind": null,
  "version": 1
}
```

有有效领用时禁止调拨厂站（409）。调拨写入调拨记录。旧帽 `bind_user_id` 不是领用人。
