# 双应用节点与麒麟部署包（开发中）

本目录对应“达梦 8 + 两组协议网关/后端 + 共享 NAS/NFS”的方案。数据库、Redis、媒体服务与入口自身没有冗余保障。当前 Compose 在一台主机运行两个应用进程，证明应用层分流与协作，不证明主机故障高可用。跨物理主机部署必须按实际内网地址拆分节点配置，并重新验证 NFS、入口健康检查和网络隔离。

**尚未作为生产包验收：** 后端全局任务/维护协调和真实双库迁移已有专项测试证据；完整双节点业务、页面/安卓、容量及麒麟实机仍需完成。不要以配置文件存在或网关测试通过替代这些门槛。验收记录见仓库 `docs/deployment/dm8-cluster-acceptance.md`。

## 组成与隔离

- `app-a/app-b` 使用同一固定数据库版本和 Redis；各有唯一稳定 node-id。每个 JVM 每次启动还会生成会话代次。
- `helmet-a/b`、`belt-a/b` 仅转发到对应后端，复用原协议校验；同一设备的凭证在两组网关保持一致。设备重连由 Caddy 分配，存量连接不迁移。
- `Caddyfile` 按设备凭证匹配协议；手机 `/wear-api` 剥一次前缀后进入原 wear 网关，福大三个 POST 查询进入原 fuda 网关。`backend-router` 只在私网将 HTTP 分给健康 app；所有代理均禁用重试。原 PC guardian 重叠接口也进入同一个 wear 网关，防止通过根路径绕过限流；只有 GET/PUT snapshot、POST business/commands 和独立 admin API 按现有鉴权进入 router。其他 API 与内部/裸设备入口拒绝。
- wear/fuda 网关各保持一个实例；手机原登录限流按来源、业务限流按 token+来源统计。不要直接复制 wear 实例并声称共享限流。Caddy 覆盖 X-Real-IP 为直接连接来源；多层入口须另配置并验证可信代理链，不能信任客户端自报 IP。
- `/helmet-media` 的 control/files/whep/hls 以及精确 SIP 地址保留到独立媒体/FreeSWITCH；路径、查询、签名、Range、CORS 与 WebSocket 不做业务转换。其他网页地址交给原 PC 静态服务，禁止将其 fallback 配成 Spring。独立静态站点的原有页面路由需在现场保持。
- `SHARED_DATA_DIR` 是已经挂载的共享根，应用看到 `/shared`；`files/` 存放 Guardian 文件和 `.wearable-store-id`，另有 `upload/hatfile/tasks` 供既有入口使用。不得让 Docker 自动创建缺失挂载目录。应用 UID/GID 为 `10001:10001`；NFS 权限由服务端显式分配。
- 生产只向审批的入口开放 80/443；应用、数据库、Redis、网关不直接暴露公网。Compose 默认只绑定主机 loopback 测试端口。

## 准备

1. 在目标主机安装经过本项目验证的 Docker Engine、Compose V2、Python 3.9 或更新版本与 bash。先运行 `kylin-preflight.sh`；默认必须是麒麟 V10 x86_64、hard NFS。`--lab` 仅用于开发，不能形成麒麟结论。
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

5. `.env` 配置非密钥的 `BACKEND_IMAGE/GATEWAY_IMAGE/MELHAT_DB_PRODUCT/SHARED_DATA_DIR/CLUSTER_PROJECT/CLUSTER_NETWORK/CADDY_SITE`；还必须填写 `PC_STATIC_UPSTREAM/MEDIA_UPSTREAM/SIP_UPSTREAM` 为已核对的独立私网 `host:port`（例如 `pc-static:80`、`media:18190`、`freeswitch:5066`，不是自动部署或默认回退地址）。按需要设置 `NODE_A_ID/NODE_B_ID/INGRESS_BIND/INGRESS_HTTP_PORT/INGRESS_HTTPS_PORT`。先创建独立 Docker 网络；外部数据库/Redis/静态/媒体依赖必须能从该网络访问。不要接入日常开发项目的数据库或共享卷。
6. 将已有设备 ID 和已有 pathToken 写入私有 `gateway-input.json`，包含 `publicOrigin/adminToken/helmets/belts`；每个设备对象为 `{deviceId,pathToken}`。adminToken 与 backend.env 一致。可设置 `deviceWebsocketOrigin`，例如特定固件需要的同域 `ws://...:80`；默认 wss，实际固件与防火墙必须验收。需要上传时提供同域的 `mediaControlOrigin/mediaSigningKey`。
7. 从后端根运行 `node local-dev/protocol-cluster/render-config.mjs deploy/cluster/private/gateway-input.json deploy/cluster/private`。Linux 已有目录必须归当前用户所有且权限为 0700；Windows 开发环境需由操作者限制目录 ACL，POSIX 模式位不能证明 ACL 安全。已有文件默认拒绝覆盖；受控变更时使用 `--replace`，停机或排空后同步替换所有节点并重建网关。工具不会生成或更换设备凭证。私有目录不得归档进公开交付包。

配置生成有 `gateway-manifest.json` 完整代次摘要，开始替换时先创建 `.gateway-config.incomplete`；中断或摘要不一致会阻止运维脚本启动/重建服务。恢复时保持设备入口排空，保全故障文件用于核对，从已保存的同一版本私有输入恢复；确认没有生成进程运行后移除该中断标记，再执行 `--replace` 完整生成，最后运行 `clusterctl.sh check`。不要逐个手改生成文件或绕过脚本启动混合版本。

更换设备路由/凭据必须有完整维护窗口：先 `stop --node a`、`stop --node b` 完成排空，再生成新代次，执行 `up`。代次标签会让 Compose 重建四个协议网关、两个 API 网关、私网 router 和 **Caddy ingress**；入口不能只重载宿主机文件，因为单文件 bind mount 及已解析的 Caddy 配置仍可能指向旧内容。`up` 检查所有运行容器的代次标签、协议配置及两份 Caddy 实际挂载摘要，确认一致后才可恢复入口。代码发布更换 Caddy 配置也须在维护窗口重建对应容器。仍有任一应用/协议网关运行时，脚本拒绝套用新代次；这不是多个容器同时热更新。

## 操作

`clusterctl.sh check` 进行配置与主机预检；`migrate` 在两个 app 都已停止时运行单独迁移进程；`up` 等待全部健康；`status`/`logs --node a` 查看状态/有限日志；`drain --node a`/`stop --node a`/`restart --node a` 先后端排空、网关关闭存量连接、确认真实 quiescent 后处理单节点。开发使用下述独立实验室配置后才可加 `--lab`。没有无条件强制停止回退；未知外部执行结果必须先核对。排空不等同于全局维护暂停，不能用单节点排空授权数据库导入。

应用启动只校验迁移版本和校验和，缺表或版本不一致会失败。空数据库也要显式迁移；业务初始管理员使用 `com.ruoyi.guardian.WearableBusinessBootstrap` 离线命令，参数为包含五份显式 JSON 的私有绝对目录（`admin-ledger.json/guardian-state.json/helmet-media-private.json/business-config.json/feature-acceptance.json`），连接与媒体加密密钥通过环境提供。初始化仅接收账号、组织及初始配置，设备/领用/绑定必须为空，媒体为 `{}`、验收为 `[]`。随后通过正式建档、领用接口建立设备及协议档案；已有业务采用 [完整迁移工具](migration/README.md)，不能将业务快照伪装成空库种子。命令要求所有应用已停止，绝不合并或覆盖已有业务。

容器日志在应用最早初始化阶段即使用 `logback-cluster.xml` 输出到控制台，由 Docker 按 10MB/3 文件轮转；不会在只读容器中创建旧 Windows 日志目录。`CLUSTER_JAVA_OPTIONS` 可显式配置已测的堆、元空间及信任库，资源测试需记录其实际值。`up` 先等待两个应用健康再启动/检查入口网关；健康检查的启动宽限不等于业务就绪。

`versions.sh` 记录系统、运行时与镜像身份，不输出环境密钥。达梦版本、字符集/兼容/严格参数、JDBC 摘要以及媒体依赖版本另行记录。库迁移、最终对账、备份恢复和回滚手册完成后才可执行切换；新库产生写入后不能直接恢复旧备份。

## 实验室独立配置

`--lab` 不是在正式部署上放宽检查。它读取单独的 `.lab.env`、`private/lab/backend.env` 和四个 `private/lab/*.json`；不复用 `private/backend.env`。需要 Compose 2.24.4 或更新版本。所有命令从后端项目根目录运行。

1. 创建独立 `wearable-lab-*` Docker 项目和网络、专用数据库/Redis容器及共享目录。依赖容器名称须为 `wearable-lab-*` 或 `wearable-*-lab`，并实际连接该实验室网络。容器名只是初筛，后续还会核对不可变容器/网络 ID 和真实网络别名。禁止使用生产数据或真实设备凭据。
2. 在 `.lab.env` 填写独立 `CLUSTER_PROJECT/CLUSTER_NETWORK/SHARED_DATA_DIR` 和镜像配置；创建权限0700的 `private/lab`，写入实验室 `backend.env`、`gateway-input.json`，设置独立共享标记。按前述生成命令将输出目录改为 `deploy/cluster/private/lab`。Windows 同样须限制目录 ACL。
3. 私有 `workload.json` 增加 `labId=wearable-lab-...` 和随机32-byte base64url `isolationProof`。用 `node deploy/cluster/prepare-lab-entry.mjs deploy/cluster/private/lab/workload.json deploy/cluster/private/lab/Caddy.lab` 生成单独入口。该入口只能绑定本机；证明值不得出现在公开日志。
4. 运行 `python3 deploy/cluster/prepare-lab-inventory.py --database-container <专用数据库容器> --redis-container <专用Redis容器>`。它只登记现有依赖，核对库/schema、Redis database、共享标记、配置摘要与真实网络连接，生成新的私有 `isolation.json`。若此目录已有正式 `.env/backend.env`，通过不同网络别名复用同一依赖实例也会被拒绝。脚本不覆盖已有清单；修改配置或重建依赖时应保留旧清单，重新核对后显式准备新清单。
5. 再运行 `clusterctl.sh --lab check/migrate/up` 等命令。每次操作重验清单；入口仅映射 `127.0.0.1:${LAB_INGRESS_PORT:-18080}`。跨主机负载测试需要另行配置受控专网，不能直接取消此本机限制。

Windows 开发机使用 `python deploy/cluster/ops.py --lab <操作>`；仅允许 Linux x86_64 Docker 引擎。文件预检验证专用目录、标记、写入/刷盘/原子改名/读回，应用就绪检查再以容器 UID 验证访问。标记字节必须是小写 UUID 加单个 LF；使用 `prepare-shared-store.py` 生成，不用 PowerShell 重写换行。正式模式仍要求实际麒麟 Linux 与 NFS，不接受 Windows 预检代替。

`test/lab-media.mjs` 与 `test/media-fixture.Dockerfile` 仅用于隔离验收：保留真实媒体 HTTP、认证及存储路径，替换 ESL/SRS 等设备依赖；实际录像明确不可用。该替身只能证明接口协作，不能证明 SIP、通话、摄像头、推流或播放通过，禁止用于正式部署。

这套校验防止本目录实验室配置误指向已登记的正式依赖，不替代操作者核对其他机器或其他目录的生产资产。完整负载步骤与结果口径见 [CAPACITY.md](CAPACITY.md)。

## 已验证与边界

既有 Node Linux 16 项、头盔 47/腰带 55 项回归通过；完整入口新增测试另见交付证据。`test/proxy.test.mjs` 运行真实入口 Caddy/私网 router/四个协议网关/两个 API 网关，以及两个测试 HTTP/WS 后端和独立依赖替身。验证手机前缀与同源别名限流、福大精确路径/原始字节/头剥离、媒体 Range/路径/SIP WebSocket、双组分流、内部路径隔离、失败写入次数、排空、后端失活摘流及完整设备配置代次重建。它不验证 Spring/DM8/Redis/NFS 业务一致性，也不证明媒体签名、票据和视频播放已通过。只应在有 Docker 和隔离资源的开发机运行，结束只清理本轮随机命名的容器和网络。

官方配置依据：[Caddy reverse_proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy)、[Compose services](https://docs.docker.com/reference/compose-file/services/)。正式部署前必须保存实际版本与复测结果。
