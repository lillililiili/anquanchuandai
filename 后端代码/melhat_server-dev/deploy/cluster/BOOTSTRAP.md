# 空业务库的显式初始化

仅用于全新、已完成SchemaMigration的空业务库。既有业务使用migration/README.md的完整迁移，不能取部分业务JSON在这里覆盖。先保留两个Created/Exited应用容器；所有应用必须停止，旧节点有效租约须过期。命令检测已有数据或schema owner时拒绝，不提供清库选项。

在操作员拥有的0700私有绝对目录准备以下五份UTF-8 JSON。下面给出字段骨架；厂站名称、登录名、角色范围和BCrypt摘要须按现场确认，不能直接使用占位符。不要把该目录放入交付包或公开日志。不要把账号列表留空后初始化，否则没有可登录的管理员。

`admin-ledger.json`（初始系统管理员内部ID保留demo-system以兼容现有全局管理权限；显示名和登录名自定，系统不会提供默认口令）：

```json
{
  "revision":1,"nextId":1,
  "sites":[{"id":"site-1","name":"<现场厂站>","code":"<现场编码>","timezone":"Asia/Shanghai","enabled":true,"version":1}],
  "roles":[{"id":"system","name":"系统管理员","builtin":true,"enabled":true,"version":1,"grants":[{"operations":["*"],"siteIds":["site-1"]}]}],
  "accounts":[{"id":"demo-system","loginName":"<现场管理员登录名>","name":"系统管理员","roleIds":["system"],"siteId":"site-1","personId":null,"builtin":true,"enabled":true,"version":1,"credentialVersion":1,"passwordHash":"<现场生成的完整BCrypt摘要>"}],
  "organizations":[],"areas":[],"people":[],"dutyShifts":[],"devices":[],"assignments":[],"history":[],"audit":[],"idempotency":{}
}
```

`passwordHash`必须是有效BCrypt字符串（$2a/$2b/$2y、成本和完整摘要）；在受控工具中交互式生成，不把明文口令写入命令行、JSON或shell历史。该示例只有一个厂站和一个管理员；上线前核对客户组织、授权范围并通过页面创建其余账号。

`guardian-state.json`：

```json
{"version":1,"seq":0,"clock":0,"stations":[],"people":[],"devices":[],"bindings":[],"locations":[],"vitals":[],"works":[],"events":[],"media":[],"groups":[],"fences":[],"fenceRecords":[],"calls":[],"broadcasts":[],"audit":[]}
```

`helmet-media-private.json`为 `{}`；`feature-acceptance.json`为 `[]`；`business-config.json`为 `{"simulatedWatchVisible":false}`。不导入设备、绑定、媒体运行态或既有验收记录。后续使用正式建档/领用接口建立业务关联，真实设备功能按实测再验收。

在后端根目录执行（沿用README中已校验的配置和代次）：

```sh
export BOOTSTRAP_DIR=/private/wearable-bootstrap
export GATEWAY_CONFIG_GENERATION="$(python3 -c 'import json; print(json.load(open("deploy/cluster/private/gateway-manifest.json"))["generation"])')"
docker compose --project-directory deploy/cluster --env-file deploy/cluster/.env \
  -f deploy/cluster/compose.yml --profile tools run --rm --no-deps \
  --user "$(id -u):$(id -g)" --volume "$BOOTSTRAP_DIR:/bootstrap:ro" \
  --entrypoint java migrate \
  -Dfile.encoding=UTF-8 -Dloader.main=com.ruoyi.guardian.WearableBusinessBootstrap \
  -cp /app/fdc-admin.jar org.springframework.boot.loader.PropertiesLauncher /bootstrap
```

容器使用当前操作员UID读取私有只读目录；连接参数和32字节Base64媒体密钥由migrate服务的private/backend.env提供，不出现在命令参数。目录须存在且五份文件可读，额外的数据库信任库或TLS设置须按现场要求配置。已有加密数据必须保留原密钥；这里不生成替代密钥。

只在命令正常退出并显示初始化提交后启动单节点，实际验证管理员登录和组织范围，再加入第二节点。失败保留原输入和错误证据，不能手工补成功标记、清schema owner或无条件重跑覆盖数据。
