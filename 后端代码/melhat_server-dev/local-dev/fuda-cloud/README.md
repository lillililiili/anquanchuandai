# 福大接口服务器部署与切换

2026-10-27 已完成本机及云端独立 staging 的快照恢复、三个数据接口和实际后端重启验证；云端四个演练容器已停止，三个卷保留。生产入口未切换，福大正式地址未开放，也未进行真实设备控制或国标媒体会话。以下恢复和切换命令仍须按相应目标及发布窗口执行，不可对已有演练库重复全量导入。福大国标参数尚缺。

## 两个独立项目

| 环境 | Compose 命令文件 | 项目名 | 对外可访问入口 |
| --- | --- | --- | --- |
| 默认演练 | `-f compose.yml` | `fuda-wearables-staging` | 仅回环 `127.0.0.1:18089` 三个查询路径 |
| 正式生产 | `-f compose.yml -f compose.production.yml` | `fuda-wearables-production` | 后端回环 `127.0.0.1:18084`，查询入口桥网 `10.255.1.1:28089` |

两个项目各自产生独立的 `mysql-data`、`redis-data`、`backend-data` 卷和网络，不使用 `local-dev` 的现有容器或数据卷。禁止通过 `-p`、`COMPOSE_PROJECT_NAME` 或其他覆盖文件改变这两个受控名称，也不要把演练卷改名或挂给生产。

默认演练的后端只连接 `internal: true` 私有网络，不发布宿主端口；**原草案的 18094 已移除**。查询网关独自跨接私有网络和普通 frontend 网络，因此宿主端口映射可用，但不能作为任意代理。MySQL/Redis 没有宿主端口。演练只挂载不含真实地址或密钥的 `safe-runtime.yml`；命令行进一步强制关闭真实的 `melhat.direct.enabled`、`melhat.belt.enabled`、`melhat.helmet-media.enabled` 和 `fuda.gb.internal-enabled`，清空媒体/GB凭据并禁用厂家默认地址。恢复的 pending 报文可以在演练库处理，但不会因此授权真实设备或媒体操作。

生产 override 才挂载私密生产 runtime、解除上述演练开关并连接 egress。设备/手机网关与替代反向隧道的私有转发只定义在生产 override 中，并额外要求 `production-device-cutover` profile。单独在默认文件上指定该 profile 不会创建设备入口。生产配置仅适用于确认拥有 `10.255.1.1` 桥网的 Linux 云宿主。

## 准备与权限

1. 使用当前功能稳定后的隔离源码构建完整后端 JAR/镜像，记录源码基线、测试、镜像摘要。Compose 至少 2.24.4，生产 override 使用 `!override` 替换端口，避免保留演练入口。
2. 分别复制 `.env.example` 为 `.env.staging` 和 `.env.production`；数据库/Redis 密码分开。两者读取旧加密媒体数据时必须使用原 `MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY`，不能重新生成。两个 env 文件与私密目录不得提交或发给福大。
3. 建立 `.private/staging/fuda-api.yml` 和 `.private/production/fuda-api.yml`，参考 `../fuda-api.example.yml`；测试、生产 AppId/密钥分开，只授权确认的真实设备。演练配置中不要放媒体、SIP或设备网关凭据。
4. 仅为生产创建 `.private/production/device-runtime.yml`：转移现有已验证的设备开关、公网 HTTP/WS 地址、超时、双钩映射、媒体控制地址和密钥引用。保持未验收功能禁用。不得保留 USB 回环设备地址。实际属性名是 `melhat.direct`、`melhat.belt`、`melhat.helmet-media`、`fuda.gb`。国标参数未到时继续保持 `fuda.gb.internal-enabled: false`。
5. 仅为生产转移原 `helmet-gateway.json`、`belt-gateway.json` 至 `.private/production/`，保留路径凭据、设备号与固定上游 `http://127.0.0.1:18084`。不要重新生成路径令牌。
6. Linux 的 env、YAML 和网关 JSON 均设置 0600，私密父目录 0700。网关镜像以 `node` 用户 UID/GID **1000:1000** 运行，因此两个 JSON 文件必须属主 1000；不能只留 root:root 0600 后期待容器读取。部署账号可以保留父目录属主，Docker 以文件为单位挂载。

仅针对已核实的两个文件设置权限的示例（不要递归修改未知目录）：

```sh
chmod 700 .private .private/staging .private/production
chmod 600 .env.staging .env.production .private/staging/fuda-api.yml .private/production/fuda-api.yml .private/production/device-runtime.yml
chown 1000:1000 .private/production/helmet-gateway.json .private/production/belt-gateway.json
chmod 600 .private/production/helmet-gateway.json .private/production/belt-gateway.json
```

配置解析不启动服务，也不需要 Docker daemon：

```sh
docker compose --env-file .env.staging -f compose.yml config --quiet
docker compose --env-file .env.production -f compose.yml -f compose.production.yml --profile production-device-cutover config --quiet
```

不要在终端打印完整 `docker compose config`，因为展开结果可能含密钥。对外协议包只包含字段和占位符。

## 演练：只恢复 staging

在源 MySQL 所在主机执行 `snapshot_export.py`，使用单事务导出，并从同一份 SQL 计算逐表记录数及摘要，再将私密快照安全传送到云宿主。源库持续写入时，不能把导出之前的独立 inventory 当作该快照的对账依据。备份文件包含账号、媒体凭据等私密数据，工具以 0600 新建文件，禁止覆盖同名文件。源仍接收上报时只把快照用于演练，不把它当作最终迁移数据。

先在将要部署的 Linux 主机执行 `python3 preflight.py --root /opt/wearables`。它检查回环 18089、私密 staging 文件权限、可用内存/磁盘；3GiB/20GiB 只是最低门槛，不代替媒体容量测试。演练后端没有 18094/18084 宿主映射。

未来执行演练时的顺序：

```sh
# 只启动独立 staging MySQL，不能先启动后端初始化表。
docker compose --env-file .env.staging -f compose.yml up -d mysql
python3 database_release.py inventory --container <源MySQL容器> > before.json
python3 database_release.py backup --container <源MySQL容器> --output <私有备份目录>/rehearsal.sql
python3 database_release.py restore-standby --target-role staging --container fuda-wearables-staging-mysql-1 --dump <备份文件> --sha256 <备份摘要>
python3 database_release.py inventory --container fuda-wearables-staging-mysql-1 > after.json
python3 database_release.py compare --before before.json --after after.json
```

上述独立 inventory/backup/compare 仅适用于源已停止写入的情况。在线演练使用 `snapshot_export.py` 生成的 `snapshot-manifest.json`，恢复后逐项核对其中 `counts` 与目标 inventory 的 `counts`，不比较两次独立采样的水位。完成核对后再启动后端，后端会新增对外报警日志和回填。

### 本轮受限演练

本机及云端均已使用真实 MySQL、Redis、后端和查询网关恢复一致快照。云端恢复 88 表、13,712 行；首轮 HTTP 11/11、实际后端重启后 12/12 通过，72 条报警分 36 页，续拉新增为 0。75 次资源采样中可用内存最低 1162 MiB、换页速率最高 0.094 MiB/s，无 OOM。结束后四个 staging 容器已停、三个卷保留；原 16 个容器受检状态未变。详见交付根目录 `STAGING-VALIDATION.md` 和 `cloud-staging-acceptance-20261027.zip`。这些结果不能替代实时设备、持续新增报警、国标、生产或公网 HTTPS 验收。

`compose.rehearsal-limited.yml` 仅用于短时低并发 staging，总内存上限 1152 MiB，禁止自动重启。使用时同时指定 `-f compose.yml -f compose.rehearsal-limited.yml`，不得混入生产配置。Linux 上先执行 `resource-watch.py --baseline`，再启动 `--watch` 监护；超过阈值只停止明确属于本次演练的容器，不删除卷。监护正常结束后不会持续保护。演练结束应停止本次容器、保留卷和报告。生产最低资源要求不因此降低。

本轮修正两项监护误判：换页按实际页大小与采样间隔计算，换入/换出合计至少 1 MiB/s 持续 30 秒才触发该条件；仅初始已停止、归属及资源限制正确的同一容器允许 120 秒启动宽限，并忽略该停止状态遗留的 unhealthy。运行后 unhealthy、OOM、退出及其他资源阈值仍生效。修正后的监护逻辑 21 项测试、原服务只读守卫 7 项测试通过。

后端数据库连接使用 `sslMode=REQUIRED`，避免 MySQL 8 认证在明文连接下拒绝启动。私密 `.env.staging` 不进入 Docker 构建上下文；独立部署包包含私密配置和快照，仅供内部部署，严禁发给福大。

恢复守卫核对项目名、服务名和 deployment-role 标签，要求目标没有任何业务表且**该目标项目**的 backend 没有运行；角色不符、非空库、旧 `local-dev` 或旧草案 `fuda-wearables` 项目一律拒绝。第一次演练失败后若留下部分表，不可绕过守卫；保存失败证据，人工核实并另行处理隔离演练目标。

SQL 导入核对后，离线迁移 `/data` 所需文件至明确命名的 staging 卷 `fuda-wearables-staging_backend-data`，保留权限/文件摘要及加密密钥。不要共享旧生产卷或实时文件目录。随后才能运行：

```sh
docker compose --env-file .env.staging -f compose.yml up -d backend redis query-gateway
```

通过 `http://127.0.0.1:18089/openapi/wearables/v2/.../query` 使用测试签名联调。演练不连接真机，在线状态可显示离线/未知；不对外宣称实时实机验收。后端启动会执行增量建表/真实报警回填，导入对账应先于启动。禁止用全量初始化 SQL 覆盖旧库。

## 正式切换：使用全新的 production 目标

1. 确认当前日常功能稳定、发布窗口与回退材料。生产项目不得已承载业务；若生产库已存在业务表，这是一次后续升级，不可重复本首次导入流程。旧 staging 保留作演练证据，不迁入生产使用。
2. 暂时关闭旧设备入口，等待已接收报文落库，记录水位、pending 数与最后通信时间，再停止旧后端写入。检查并记录实际旧进程/容器已经停止写入；云端脚本无法证明远端电脑已停，不能把云端空闲端口当作单写端证明。
3. 从此时静止的源重新备份最终 SQL 和必要文件。**不使用演练快照**。生产使用新项目、新空卷：

```sh
docker compose --env-file .env.production -f compose.yml -f compose.production.yml up -d mysql
python3 database_release.py restore-standby --target-role production --container fuda-wearables-production-mysql-1 --dump <切换时最终备份> --sha256 <最终备份摘要>
python3 database_release.py inventory --container fuda-wearables-production-mysql-1 > production-after.json
python3 database_release.py compare --before <最终源inventory.json> --after production-after.json
```

4. 在生产后端未启动时迁移必要 `/data` 文件至独立 `fuda-wearables-production_backend-data` 卷，核对文件摘要、人员绑定、设备、报警和待处理原始报文。已有云媒体资产保持原位置。保留唯一生产写入端，不能同时恢复旧端入口。
5. 用准确的旧进程/服务标识停止云端三个旧反向隧道，核实桥网监听释放；不要广泛终止 SSH。运行 `python3 preflight.py --root /opt/wearables --production`，它要求 Linux、真实 `10.255.1.1` 网卡地址、回环 18084/18086/18087/18088 与桥网 28086/28087/28088/28089 全部空闲，并核对生产私密文件模式和网关 UID。切换前旧监听仍占用时检查理应失败；脚本不会替你结束它们。
6. 构建好生产网关镜像后，先执行下面的纯配置检查；`--no-deps` 不启动后端，网关 `--check` 不监听端口、不连接设备。此步骤会创建短时检查容器，应仅在正式操作时执行，本次未执行：

```sh
docker compose --env-file .env.production -f compose.yml -f compose.production.yml --profile production-device-cutover run --rm --no-deps helmet-gateway node cli.mjs --check
docker compose --env-file .env.production -f compose.yml -f compose.production.yml --profile production-device-cutover run --rm --no-deps belt-gateway node cli.mjs --check
```

7. 对账、权限及单写端确认后，才启动生产，并向已有站点增量加入 `Caddy.routes.example` 三个 POST 路径；Caddy validate 成功后 reload，保留其他网站和设备路径：

```sh
docker compose --env-file .env.production -f compose.yml -f compose.production.yml --profile production-device-cutover up -d --build
```

生产固定后端 18084 与网关上游一致，私有 TCP 转发在桥网 28086/28087/28088 替代旧隧道。查询网关是桥网 28089，仅转发三类查询，不开放 `/internal` 或整个后台。

8. 核对真机重新登录、上报入库、原有三端功能、福大鉴权与游标。关闭开发电脑后复核，确保没有残留本地依赖。窗口内断线与重连需记录，不宣称未经实测的无损迁移。监测错误率、延迟、最后通信时间、报警水位、磁盘及视频会话；先以当前两台设备范围运行。

视频组件单独见 `../fuda-gb-bridge/`。生产 Java 地址应配置为 `GB_JAVA_ORIGIN=http://127.0.0.1:18084`（同一云宿主），其内部 HMAC、白名单和 GB 开关需单独核对。缺福大参数时继续禁用 GB；不得把内部 GB 路由加到公网查询代理。

## 回退与验证边界

路由切换前可独立停止 staging 项目，无需切换日常服务入口。生产未切换及原容器受检状态未变，不保证共享主机上原业务性能无任何影响。生产接收新上报后，先保存最新 SQL、接收日志和文件，再按已确认的恢复方案迁回、对账并切换；不能恢复旧 dump 丢弃新报警或轨迹。非空库守卫不能为回退临时关闭。禁止 `docker compose down -v` 删除业务卷。

可离线运行 `python3 -B -m unittest test_database_release.py test_preflight.py test_compose_isolation.py`。测试使用 mocked 容器/网络检查及 `docker compose config` 解析，不连接数据库、不监听端口、不启动容器。本轮另已实际完成云端 staging 构建、配置挂载、真实数据库恢复及 localhost HTTP 验证；生产配置、对外网络、持续真实上报和国标点播仍须实际验收。部署配置及监护修正未重建候选 JAR，其摘要见交付根目录 `STAGING-VALIDATION.md`。
