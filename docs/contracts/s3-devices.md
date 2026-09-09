# S3 设备台账与型号能力契约

版本：S3　依赖：[00-common.md](00-common.md)、[s1-auth.md](s1-auth.md)

帽和带共用 Device 台账。能力来自 **型号**，不能由类型名（安全帽）自动赋予视频。旧 `safety_hat_info.hat_number` 仍是厂商标识，本阶段不改号、不切流。厂站范围与 `X-Site-Id` 规则同 S1。

## 1 能力

型号 `capabilities`：

```json
{
  "protocolVersion": "demo-hat-v1",
  "attributes": ["battery", "online", "gnss"],
  "events": ["sos", "fall"],
  "actions": ["tts", "intercom", "video"]
}
```

客户端用 `actions` / `attributes` / `events` 控制入口。无 `video` 则无视频入口。禁止写死「安全帽一定有视频」。

## 2 资产与连接

- 资产 `assetStatus`：`unassigned` | `in_stock` | `maintenance` | `disabled` | `scrapped`
- 连接：`online`、`battery`、`lastReportedAt` 可空。新建为 `null`，表示未知，**不是**离线也不是在线。
- `source`：本阶段为 `db`。演示数据可带 `demo: true`，不得当作真实在线。

未分配厂站（`siteId` 空）仅平台管理员 / 若依 admin 可见。值班、只读、设备管理员列表中不出现未分配设备。

## 3 权限

| 能力 | 角色 |
| --- | --- |
| 设备列表/详情、型号查询 | 值班、班组长、复核、只读、设备管理员、平台管理员 |
| 设备/型号写入、分配厂站 | 设备管理员、平台管理员、若依 admin |
| 未分配设备、旧帽映射预览 | 平台管理员、若依 admin |

权限字：`wear:device:list|query|edit`，`wear:model:list|edit`。

只读写入 403。隐藏按钮 ≠ 已授权。

## 4 设备接口 `/api/v1/devices`

分页 `GET /api/v1/devices?current&size&typeCode&modelId&sn&assetStatus`  
范围：当前厂站；未选当前站时为授权厂站并集。跨站设备不出现。未分配设备不出现在非平台账号结果中。

详情 `GET /api/v1/devices/{id}`：无授权则 403。含型号能力与 `legacyHatId`（无映射则为 `null`）。

登记 `POST /api/v1/devices`：`manufacturerCode`、`sn`、`modelId` 必填。连接字段忽略客户端传入，服务端置空。缺厂站且非平台管理员 → 400「请选择厂站」。同一厂商 SN 重复 → 409。

修改 `PUT /api/v1/devices/{id}`：带 `version`，冲突 409。

分配厂站 `PUT /api/v1/devices/{id}/site`：`{ "siteId": "1", "version": 1 }`。`siteId` 空表示撤销分配。目标厂站必须在账号授权内。

资产状态 `PUT /api/v1/devices/{id}/asset-status`：`{ "assetStatus": "disabled", "version": 1 }`。

旧帽预览 `GET /api/v1/devices/legacy-preview`：尚未映射的 `safety_hat_info`，只读，不写库。

设备对象：

```json
{
  "id": "1",
  "manufacturerCode": "MELHAT",
  "sn": "MH-DEMO-001",
  "externalCode": "MH-DEMO-001",
  "modelId": "1",
  "modelCode": "HAT-MH-CAM",
  "modelName": "演示摄像安全帽",
  "typeCode": "helmet",
  "siteId": "1",
  "siteName": "演示厂站A",
  "assetStatus": "in_stock",
  "online": null,
  "battery": null,
  "lastReportedAt": null,
  "capabilities": {
    "protocolVersion": "demo-hat-v1",
    "attributes": ["battery", "online", "gnss"],
    "events": ["sos", "fall"],
    "actions": ["tts", "intercom", "video"]
  },
  "legacyHatId": "1",
  "source": "db",
  "demo": true,
  "version": 1
}
```

## 5 型号 `/api/v1/product-models`

- `GET /api/v1/product-models?typeCode=`
- `GET /api/v1/product-models/{id}`
- `POST /api/v1/product-models`、`PUT /api/v1/product-models/{id}`（带 `version`）

`typeCode` 仅为 `helmet` | `belt`。`modelCode` 全局唯一。

## 6 SN 与旧帽

唯一范围：`(manufacturerCode, sn)`，数据库约束兜底。帽号不是平台主键。映射表一对一关联旧帽 ID，正式停用旧表在 S11。
