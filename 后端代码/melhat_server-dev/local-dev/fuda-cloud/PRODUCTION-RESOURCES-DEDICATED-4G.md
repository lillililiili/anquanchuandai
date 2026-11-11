# 2 核 / 4 GiB 主机穿戴系统资源试验方案

本方案按暂停知识库八项应用、保留其数据库文件后评估。共享 Caddy、现用五项媒体服务及福大实时查询网关继续运行。配置尚未部署；通过配置或资源检查不代表生产验收通过，不授权切换入口、重启现有服务或用旧快照接管业务。

## 预算与前提

| 服务 | 内存上限 |
| --- | ---: |
| backend | 896 MiB；Xms 256 MiB、Xmx 512 MiB |
| MySQL | 448 MiB；buffer pool 96 MiB、最多 30 个连接 |
| Redis | 128 MiB；maxmemory 48 MiB、noeviction |
| query-gateway | 64 MiB |
| helmet / belt / phone 网关 | 各 96 MiB |
| private-relays | 64 MiB |
| 合计 | **1888 MiB** |

没有新增 CPU 硬配额；每个容器 memswap_limit 等于内存上限。日志每文件 10 MiB、最多 3 个，八个容器约 240 MiB 日志预算。内存上限不是预留量，也不覆盖既有媒体、Caddy、内核及主机缓存。

独立试验准入为：Linux、至少 2 核，在暂停其他项目后连续至少 300 秒采样，间隔不超过 15 秒，**每个样本 MemAvailable ≥2400 MiB、目标磁盘空闲 ≥20 GiB**。这为 1888 MiB 预算留下约 512 MiB 的已观测余量。swap 存量不直接判失败；换入与换出总速率若达到 1 MiB/s 并持续 30 秒则拒绝准入。这只是受监护试验准入，不能代替完整业务压力和故障恢复验收。

原 `preflight.py` 默认 3 GiB / 20 GiB 门槛完全不变。此方案以暂停知识库后取得的资源窗口和后续完整实测为依据，最后才能评审适用于该专用方案的正式验收条件；不以“改低门槛通过”代替验证。

## 参数来源与保留范围

本次只读核查本机正在运行的 `melhat-backend`，未发现 JAVA_TOOL_OPTIONS、JDK_JAVA_OPTIONS 或 _JAVA_OPTIONS。守卫遇到已有非空 JVM 选项会拒绝静默覆盖，要求重新核对。896 MiB 上限给 512 MiB 堆之外保留 384 MiB 余量，是否足够仍需实测；profile、设备开关、地址、镜像、卷和凭据不由此层修改。

现用 Redis 启动显式启用 AOF，并未强制每次写入 fsync。本方案明确使用 `appendfsync everysec`、`no-appendfsync-on-rewrite no`，避免引入 8 GiB 未选用草案的 always 策略。保留密码环境引用、AOF和持久卷；noeviction 防止容量压力驱逐 nonce，但超过容量时 Redis 写入可能失败，应监控和验证失败处理。AOF 重写额外内存与磁盘延迟需要实测。

everysec 对异常断电存在最近写入丢失窗口，不能把此前正常停止/启动的 nonce 测试当作断电保证。如业务需要更严格的跨崩溃防重放，应另行评审持久化和性能方案，而不是在这次资源调整中静默改变策略。[Redis 官方持久化说明](https://redis.io/docs/latest/operate/oss_and_stack/management/persistence/)

## 只读检查

固定文件顺序：

```text
--env-file .env.production -f compose.yml -f compose.production.yml -f compose.production-resources-dedicated-4g.yml
```

仅检查配置（不启动容器，不连接 Docker daemon，原始配置和错误输出不打印）：

```sh
python3 production_resources_4g_check.py --env-file .env.example
python3 production_resources_4g_check.py --env-file .env.production
python3 -B -m unittest test_production_resources_4g.py test_production_resources.py test_compose_isolation.py test_preflight.py
```

资源层没有项目名、镜像、构建路径、网络或端口。漏掉 production override 时新增网关缺失 build/image，Compose 会拒绝解析；守卫还会拒绝 staging、8 GiB预算、任意项目改名和越界字段变化。它不把通过配置检查显示成 productionReady。

在实际 Linux 目标上取得一个不含秘密的数字样本：

```sh
python3 production_resources_4g_check.py --sample-host --host-root /home/admin
```

按不超过15秒间隔收集至少300秒，将这些原样样本组成JSON数组后检查：

```sh
python3 production_resources_4g_check.py --host-window /absolute/private/host-window.json
```

`--host-window` 仅校验已有观测，不控制服务；`trialHostAdmissionPassed` 与 `configurationPassed` 必须分别满足，且都不等同生产就绪。若 Docker 数据卷、发布包和备份不在同一文件系统，应分别检查其空闲空间，不能用另一个磁盘的剩余空间替代。当前云主机数据盘布局还应由操作者核对。

## 试验通过后才评审生产

先在受监护隔离目标验证：资源限制下恢复启动、数据库持续写入、两台设备实际报文速率、PC/手机常用操作、三个福大接口、报警增量、Redis AOF重写、至少一路既有音视频。记录原媒体/Caddy/查询入口状态、OOM、容器退出、Redis拒写、CPU与磁盘延迟、处理水位和积压。

完整业务负载下若余量不足，不强行上线；修订预算或功能范围后重新验证。隔离候选的自动停止保护不能原样用在已接管设备的正式写入端。发布物须固定，当前工作区 target JAR 与已验收运行JAR不相同；最后重新备份/核对水位、报警和文件，保持唯一写入端及可回退路径，再安排切换。
