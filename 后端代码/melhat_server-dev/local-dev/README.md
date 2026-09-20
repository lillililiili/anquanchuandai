# 本地设备接入模式

## 已有数据库升级（页面缺字段报错）

Docker 的 `/docker-entrypoint-initdb.d` 脚本只在数据卷首次初始化时执行。
已有数据库不会因为重启或重新构建镜像而自动补列。
遇到 `sys_dept.dept_code` 或 `electronic_fence_alarm.fence_id` 缺失时，
使用 `sql/migrations/20260916_page_schema.sql` 做增量迁移，不要重跑包含 DROP TABLE 的完整初始化脚本。
此迁移只补充缺失的可空字段和索引，可重复执行，不删除或改写现有业务记录。
历史围栏告警的 `fence_id` 留空，不能用 `hat_id` 猜测围栏归属。

在本目录通过 PowerShell 执行：

```powershell
Get-Content -Raw ../sql/migrations/20260916_page_schema.sql | docker exec -i melhat-mysql sh -c 'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD" --default-character-set=utf8mb4 new-helmet'
```

默认 `MELHAT_DEMO_MODE=false`：走原有真实设备服务，不将调用失败转为模拟成功。
旧页面的模拟兼容接口仅在 `true` 时注册；真实模式下这些尚无真实实现的接口返回未找到，不冒充真实数据。

在本目录创建 `.env`，参考 `.env.example` 填写平台提供的账号凭据。
不要把平台凭据提交到 Git，也不要在聊天中粘贴密码。
默认平台地址使用 HTTP，凭据传输不加密；真实环境应向平台确认 HTTPS 地址或使用受信网络。

重新构建后端 JAR 后，在本目录执行：

```powershell
docker compose up -d --build --no-deps backend
```

仅离线演示时设置 `MELHAT_DEMO_MODE=true`，重新创建 backend 容器。
该模式下对讲、广播只保存本地记录，不调用真实 RTC/TTS。

切换模式不会清空数据库。已有 MH-DEMO-* 记录仍是模拟数据，不能作为设备已在线的证据。
连接验证应先检查认证及设备列表，获得授权后再验证真实通话/广播。

## 真实设备清单同步

真实模式下，管理员登录后可使用以下接口（携带后台登录 Token）：

- `GET /hat/safety/info/platform/devices`：只读预览账号下的平台设备。
- `POST /hat/safety/info/platform/sync`：按 SN 同步设备，返回新增、更新、未变和跳过已删除记录的数量。

同步只新增缺失设备或更新已有设备的平台状态/通信标识，保留已有人员、群组及媒体配置。
新增设备的人员和群组绑定留空。已软删除的设备不自动恢复；重复编号或无效平台状态会中止同步。
没有平台匹配的旧记录仍保留，查询显示 `平台未确认`（状态 `-1`），不计入在线/离线统计。
设备列表与状态筛选使用平台查询结果；查询失败会报错，不以数据库旧状态替代。
只有只读设备查询在收到 401 时会刷新认证并重试一次，通话和广播不自动重放。

需要设备上线后才能验收：实时定位与时间戳、视频、对讲、广播、SOS/告警上报。
导入设备编号并不代表这些能力已经验证；离线设备的旧坐标也不代表当前位置。
