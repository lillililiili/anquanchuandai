# S1 身份与厂站契约

版本：S1　依赖：[00-common.md](00-common.md)

登录、退出继续使用若依路径。当前用户、厂站范围以 `/api/v1` 为准。隐藏按钮不代表服务端已授权。

## 1 角色与帽子操作（首版）

| role_key | 名称 | 授权厂站帽子列表/详情 | 帽子写入 | 厂站授权维护 |
| --- | --- | --- | --- | --- |
| `wear_platform_admin` | 平台管理员 | 全部厂站 | 是 | 是（本阶段以迁移种子为主） |
| `admin` | 若依超级管理员 | 全部厂站 | 是 | 是 |
| `wear_device_admin` | 设备管理员 | 授权厂站 | 是 | 否 |
| `wear_duty` | 值班员 | 授权厂站 | 否 | 否 |
| `wear_reviewer` | 安全复核员 | 授权厂站 | 否 | 否 |
| `wear_team_lead` | 班组长 | 授权厂站 | 否 | 否 |
| `wear_readonly` | 只读 | 授权厂站 | 否 | 否 |

平台管理员不能因此自动成为值班认领人（认领在 S5）。事件处置、通话、人员台账权限标为未开放。

权限字（出现在 `/api/v1/me`.permissions）：

- `wear:hat:list` `wear:hat:query` `wear:hat:edit`
- `wear:site:list` `wear:site:select`

## 2 接口

### 2.1 兼容入口

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| POST | `/login` | `{ username, password, code?, uuid? }` → `{ code, token }` |
| POST | `/logout` | 删除 Redis 会话 |
| GET | `/getInfo` | 旧 PC 仍可用；新逻辑不要只依赖它 |

账号停用后登录失败。已登录 token 在停用后立即 401。

### 2.2 `GET /api/v1/me`

需要登录。`data`：

```json
{
  "userId": "1",
  "userName": "admin",
  "nickName": "管理员",
  "status": "0",
  "admin": true,
  "roles": ["wear_platform_admin"],
  "permissions": ["wear:hat:list", "wear:hat:query", "wear:hat:edit", "wear:site:list", "wear:site:select"],
  "authorizedSites": [
    { "id": "1", "siteCode": "SITE-DEMO-A", "name": "演示厂站A", "status": "0", "timezone": "Asia/Shanghai", "version": 1 }
  ],
  "currentSiteId": "1"
}
```

无 `password`。`status=0` 正常，`1` 停用。`currentSiteId` 可为 `null`。

### 2.3 `GET /api/v1/sites`

仅返回当前账号有效授权且厂站 `status=0` 的列表。空数组表示无厂站，不是失败。

### 2.4 `PUT /api/v1/me/current-site`

```json
{ "siteId": "1" }
```

`siteId` 必须在授权列表中，否则 403。成功 `data`：`{ "currentSiteId": "1" }`。

### 2.5 请求头 `X-Site-Id`

可选。若出现，必须是授权厂站，否则 403。用于覆盖本次请求的当前厂站，**不**自动写回会话。会话当前站只由 `PUT /api/v1/me/current-site` 更新。

未选当前站且授权多于一个：帽子列表按授权并集过滤；帽子写入返回 400「请选择厂站」。

未分配 `site_id` 的旧帽子仅平台管理员可见。

## 3 错误

| 场景 | code | 提示方向 |
| --- | --- | --- |
| 未登录 / token 失效 / 已退出 / 已停用 | 401 | 未登录或登录已过期，请重新登录 |
| 厂站不在授权范围 / 只读写帽子 | 403 | 没有权限执行该操作 |
| 多厂站未选择当前站却写入 | 400 | 请选择厂站 |

## 4 帽子范围（S1 试点）

现有 `/hat/safety/info/page|list|{id}|save|updte` 必须走同一套厂站校验。A 站账号不得看到 B 站帽子。只读角色 `save`/`updte`/`delete` 为 403。
