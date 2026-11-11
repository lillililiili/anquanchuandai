# 8 GiB 主机初始生产资源草案

**当前未选用本草案。** 当前部署方向为保留现有 2 核 / 4 GiB 主机、评估暂停其他项目后的穿戴系统容量。此文件仅保留作预算参考，不能据此直接部署，也不构成要求升级服务器的结论。4 GiB 专用方案需要根据腾出后的资源和完整工作负载另行验证。

此配置**未启用、未部署，尚未实测**。仅为同时保留知识库和现有媒体服务的 8 GiB 主机准备初始资源预算；不适用于直接在当前约 4 GiB 主机上切换生产，也不修改 `preflight.py` 的 3 GiB 可用内存 / 20 GiB 空闲磁盘门槛。

| 服务 | 容器内存上限 |
| --- | ---: |
| backend | 1024 MiB（JVM Xms 256 MiB、Xmx 512 MiB） |
| mysql | 512 MiB（buffer pool 128 MiB、最多 40 个连接） |
| redis | 128 MiB（maxmemory 48 MiB、noeviction） |
| query-gateway | 64 MiB |
| helmet-gateway、belt-gateway、phone-gateway | 各 96 MiB |
| private-relays | 64 MiB |
| 合计 | **2080 MiB** |

上限不是预留量或容量承诺。relay 从初步讨论的 32 MiB 增至 64 MiB，以免 Node 基础进程余量过小；该数值仍需实测。容器不使用额外 swap，不新增 CPU 硬配额。每个容器使用 `json-file`，每文件最多 10 MiB，最多 3 个文件；八服务容器日志预算约 240 MiB，不包括业务文件、MySQL、AOF及宿主日志。

Redis 保留原密码环境引用和持久卷，明确启用 AOF、`appendfsync always`、`no-appendfsync-on-rewrite no`。`noeviction` 避免因容量压力驱逐防重放 nonce，但达到容量后写请求可能失败，必须监控。maxmemory 留出进程和 AOF 重写余量，实际峰值仍需测量。每次写入 fsync 的磁盘延迟也需要验收；此草案不声称已经通过断电恢复。[Redis 官方持久化说明](https://redis.io/docs/latest/operate/oss_and_stack/management/persistence/)

## 只读检查

以下命令只解析配置，不调用 Docker daemon、不创建或启停容器，输出不含完整环境或密码：

```sh
python3 production_resources_check.py --env-file .env.example
python3 -B -m unittest test_production_resources.py test_compose_isolation.py test_preflight.py
```

准备好私密生产环境文件后，使用同一只读检查：

```sh
python3 production_resources_check.py --env-file .env.production
```

守卫按固定顺序解析 `compose.yml`、`compose.production.yml`、`compose.production-resources-8g.yml`，检查八个服务、生产角色、切换 profile、原有端口/私网和私密挂载，然后只允许预算中列出的内存、日志、Java 堆、MySQL 容量和 Redis 参数变化。密码引用、业务 profile/开关、地址、镜像和卷均须保持。不会打印原始 Compose 解析错误，因为错误可能包含秘密值。

资源文件没有项目名、镜像、构建目录、网络、端口或业务配置。遗漏 production override 时，新增网关缺少镜像/构建定义，Compose 会拒绝解析；守卫另外拒绝 staging 和任意改名项目。不要把 staging/rehearsal override 混入，也不要绕过守卫或用 `-p` 改名。[Docker 官方合并规则](https://docs.docker.com/reference/compose-file/merge/)

通过本检查只是配置正确，不代表可上线。今后经发布验收使用时，文件顺序必须是：

```text
--env-file .env.production -f compose.yml -f compose.production.yml -f compose.production-resources-8g.yml
```

本说明刻意不提供自动启动或切换命令。资源配置不会自行替代原生产文件；需明确加入上述第三文件才生效。

## 上线前仍需完成

1. 固定实际发布 JAR/镜像摘要。当前工作区 target JAR 与已验收运行快照的 JAR 大小不同，不能直接 `up --build` 混用；最新未提交源码应先隔离构建与验收。
2. 核对实际 Spring profile。当前源码默认 dev，资源层不擅自切换 profile、设备开关或公网地址。
3. 完成实际主机容量预检，以及设备持续上报、PC/手机操作、福大查询、MySQL/Redis连接压力、AOF重写峰值、媒体并发、资源限制下启动恢复验证。原服务必须继续正常。
4. 测量 Redis 拒写、OOM、容器重启、CPU/磁盘延迟、报文处理积压和未知字段；根据证据调整预算，不将短时测试当作长期容量保证。
5. 按现有迁移手册进行最终备份、水位/报警/文件对账、唯一写入端切换与回退准备。不得直接把旧候选快照当作当前生产库。
