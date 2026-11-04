# 双应用节点与麒麟部署包（开发中）

本目录对应“达梦 8 + 两组协议网关/后端 + 共享 NAS/NFS”的方案。数据库、Redis、媒体服务与入口自身没有冗余保障。当前 Compose 在一台主机运行两个应用进程，证明应用层分流与协作，不证明主机故障高可用。跨物理主机部署必须按实际内网地址拆分节点配置，并重新验证 NFS、入口健康检查和网络隔离。

**尚未作为生产包验收：** 后端全局任务/维护协调、数据迁移、完整双节点业务与麒麟实机仍需完成。不要以配置文件存在或网关测试通过替代这些门槛。验收记录见仓库 `docs/deployment/dm8-cluster-acceptance.md`。

## 组成与隔离

- `app-a/app-b` 使用同一固定数据库版本和 Redis；各有唯一稳定 node-id。每个 JVM 每次启动还会生成会话代次。
- `helmet-a/b`、`belt-a/b` 仅转发到对应后端，复用原协议校验；同一设备的凭证在两组网关保持一致。设备重连由 Caddy 分配，存量连接不迁移。
- `Caddyfile` 按设备凭证匹配协议，按健康状态轮询；其余业务地址保留，内部管理/裸设备入口封闭。失败写入没有代理重试。既有 PC 静态站点、福大白名单路由与媒体服务继续使用原入口配置，合并时必须保留其鉴权/签名/访问控制。
- `SHARED_DATA_DIR` 是已经挂载的共享根，应用看到 `/shared`；`files/` 存放 Guardian 文件和 `.wearable-store-id`，另有 `upload/hatfile/tasks` 供既有入口使用。不得让 Docker 自动创建缺失挂载目录。应用 UID/GID 为 `10001:10001`；NFS 权限由服务端显式分配。
- 生产只向审批的入口开放 80/443；应用、数据库、Redis、网关不直接暴露公网。Compose 默认只绑定主机 loopback 测试端口。

## 准备

1. 在目标主机安装经过本项目验证的 Docker Engine、Compose V2、Python 3 与 bash。先运行 `kylin-preflight.sh`；默认必须是麒麟 V10 x86_64、hard NFS。`--lab` 仅用于开发，不能形成麒麟结论。
2. 显式准备共享目录与权限；使用 `prepare-shared-store.py /mnt/wearable/files <UUID>` 创建唯一标记，重复执行不能更换已存在标记。记录 UUID，并在两个节点配置相同值。备份/恢复必须连标记、文件、数据库指针一起处理。
3. 构建已经测试过的后端 jar，再从后端根目录构建 `deploy/cluster/backend.Dockerfile` 和 `gateway.Dockerfile`。镜像运行 Java 17、Node 24.16.0，基础镜像和 Caddy 2.10.2 固定摘要。正式 `.env` 的 BACKEND_IMAGE/GATEWAY_IMAGE 必须使用实际验收镜像摘要或本地不可变 image ID，不填写浮动标签。
4. 创建权限 0700 的 `private/`。`backend.env` 权限 0600，设置下列参数。两节点共享 JWT/媒体加密密钥/Redis，不要重新生成已有数据使用的加密密钥。

```
MELHAT_DB_PRODUCT=dm8
MELHAT_DB_URL=jdbc:dm://<private-db>:5236
MELHAT_DB_USERNAME=<application-schema>
MELHAT_DB_PASSWORD=<private>
CLUSTER_REDIS_HOST=<private-redis>
CLUSTER_REDIS_PORT=6379
CLUSTER_REDIS_DATABASE=0
CLUSTER_REDIS_PASSWORD=<private>
JWT_SECRET=<existing-shared-secret>
MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY=<existing-base64-key>
MELHAT_FILES_STORE_ID=<UUID>
MELHAT_CLUSTER_ADMIN_TOKEN=<32-byte-base64url-token>
```

另按已有业务配置启用直连头盔、腰带、媒体与福大接口；实验环境只使用模拟设备、假媒体和禁止真实推送的配置。上述骨架不默认启用任何真实设备控制或外部推送。禁止把“关闭功能后启动成功”计作全业务验收。

5. `.env` 配置非密钥的 `BACKEND_IMAGE/GATEWAY_IMAGE/MELHAT_DB_PRODUCT/SHARED_DATA_DIR/CLUSTER_PROJECT/CLUSTER_NETWORK/CADDY_SITE`；按需要设置 `NODE_A_ID/NODE_B_ID/INGRESS_BIND/INGRESS_HTTP_PORT/INGRESS_HTTPS_PORT`。先创建独立 Docker 网络；外部数据库/Redis必须能从该网络访问。不要接入日常开发项目的数据库或共享卷。
6. 将已有设备 ID 和已有 pathToken 写入私有 `gateway-input.json`，包含 `publicOrigin/adminToken/helmets/belts`；每个设备对象为 `{deviceId,pathToken}`。adminToken 与 backend.env 一致。可设置 `deviceWebsocketOrigin`，例如特定固件需要的同域 `ws://...:80`；默认 wss，实际固件与防火墙必须验收。需要上传时提供同域的 `mediaControlOrigin/mediaSigningKey`。
7. 从后端根运行 `node local-dev/protocol-cluster/render-config.mjs deploy/cluster/private/gateway-input.json deploy/cluster/private`。Linux 已有目录必须归当前用户所有且权限为 0700；Windows 开发环境需由操作者限制目录 ACL，POSIX 模式位不能证明 ACL 安全。已有文件默认拒绝覆盖；受控变更时使用 `--replace`，停机或排空后同步替换所有节点并重建网关。工具不会生成或更换设备凭证。私有目录不得归档进公开交付包。

配置生成有 `gateway-manifest.json` 完整代次摘要，开始替换时先创建 `.gateway-config.incomplete`；中断或摘要不一致会阻止运维脚本启动/重建服务。恢复时保持设备入口排空，保全故障文件用于核对，从已保存的同一版本私有输入恢复；确认没有生成进程运行后移除该中断标记，再执行 `--replace` 完整生成，最后运行 `clusterctl.sh check`。不要逐个手改生成文件或绕过脚本启动混合版本。

更换设备路由/凭据必须有完整维护窗口：先 `stop --node a`、`stop --node b` 完成排空，再生成新代次，执行 `up`。代次标签会让 Compose 重建四个网关和 **Caddy ingress**；入口不能只重载宿主机文件，因为单文件 bind mount 及已解析的 Caddy 配置仍可能指向旧内容。`up` 检查所有运行容器的代次标签和挂载文件摘要，确认一致后才可恢复入口。仍有任一应用/网关运行时，脚本拒绝套用新代次；这不是多个容器同时热更新。

## 操作

`clusterctl.sh check` 进行配置与主机预检；`migrate` 在两个 app 都已停止时运行单独迁移进程；`up` 等待全部健康；`status`/`logs --node a` 查看状态/有限日志；`drain --node a`/`stop --node a`/`restart --node a` 先后端排空、网关关闭存量连接、确认真实 quiescent 后处理单节点。开发可加 `--lab`。没有无条件强制停止回退；未知外部执行结果必须先核对。排空不等同于全局维护暂停，不能用单节点排空授权数据库导入。

应用启动只校验迁移版本和校验和，缺表或版本不一致会失败。空数据库也要显式迁移；业务初始管理员/导入必须使用后续专用初始化与迁移工具，不使用旧实例自动回填示例数据。

`versions.sh` 记录系统、运行时与镜像身份，不输出环境密钥。达梦版本、字符集/兼容/严格参数、JDBC 摘要以及媒体依赖版本另行记录。库迁移、最终对账、备份恢复和回滚手册完成后才可执行切换；新库产生写入后不能直接恢复旧备份。

## 已验证与边界

Node Linux 16 项测试、既有头盔 47/腰带 55 项回归通过。`test/proxy.test.mjs` 运行真实 Caddy/四个网关容器和两个测试 HTTP/WS 后端，验证双组分流、内部路径隔离、失败写入次数、排空、后端失活摘流及完整配置代次重建。它不验证 Spring/DM8/Redis/NFS 业务一致性。只应在有 Docker 和隔离资源的开发机运行，结束只清理本轮随机命名的容器和网络。

官方配置依据：[Caddy reverse_proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy)、[Compose services](https://docs.docker.com/reference/compose-file/services/)。正式部署前必须保存实际版本与复测结果。
