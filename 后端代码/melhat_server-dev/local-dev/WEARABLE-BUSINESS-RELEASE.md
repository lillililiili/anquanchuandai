# 三设备业务整理：备份、演练与回滚

工具：`wearable-business-release.py`。所有含账号、环境变量、媒体凭据、原始业务数据的文件只保存在 Git 忽略的 `build/wearable-release-*`。控制台只输出计数和状态。不要将整个备份目录上传到代码库。

## 先预览，再隔离演练

```powershell
python local-dev/wearable-business-release.py preview
python local-dev/wearable-business-release.py stage <上一步目录>
python local-dev/wearable-business-release.py stage <同一目录> --image <待验证镜像>
python local-dev/verify-wearable-business-stage.py <同一目录>
```

`preview` 不停止或修改日常服务。保存完整 MySQL dump、完整 `/data` 归档及媒体文件清单、监护和媒体 JSON、容器配置、媒体加密密钥、客户端构建/配置哈希及当前工作区差异。已迁入 SQL 的系统使用当前 SQL 导出作为状态来源；文件仅作为兼容备份。在线预览不是跨存储一致的发布水位，真正切换时还会停止写者并重新备份。

`stage` 创建独立 `--internal` Docker 网络及独立 MySQL，数据库不接入日常网络。先恢复完整 dump，逐表核对实际行数，再执行归档和精确清理。启动可选验证后端时使用独立 Redis、数据目录和 `127.0.0.1:18085`，明确关闭安全帽、安全带、厂家、媒体及 Quartz；内部网络另阻断外部访问。可先仅验证数据库，再附加镜像启动后端。

部分 Docker 版本不会为内部网络实际发布主机端口；健康检查和验收直接通过 `docker exec` 在隔离容器内请求 loopback HTTP，不增加可外联网络。中断后的未验收演练会先核对归属、停止私有写者，再重建仅该隔离容器中的数据库并重验恢复计数。发布同时核对清理脚本、验收脚本和镜像摘要，任一变化必须重新演练。

`verify-wearable-business-stage.py` 先检查容器名称、归属标签、内部网络、监听端口及禁用的接入参数，再使用已记录的本地联调管理员账号正常登录隔离副本。验证前后台和移动端三个接口视图一致、隐藏手表不删除设备；维护暂停后仅在隔离库插入明确标记的 QA 报文，验证导入不覆盖新增报文、重启仍暂停且空业务集合不重新生成种子、恢复后重放更新 SQL。此项通过后才允许 `release`。验证会修改隔离副本，所有会话和导出只写忽略目录。

保留台账 `device-12`、`device-13`、`RL-W001`；保留监护设备 `866652021714127`、`866652023095053`、`RL-W001`。保留模拟表既有单一领用关系，不创建替代设备或把实机绑定演示人员。保留全部现用账户和权限，解除已归档预置人员与操作员账户的关联。

真实设备事件、定位和通信记录保留。明确 `demo` 数据、原始种子配置及非当前设备转入 `wearable_cleanup_archive` 和私密 JSON；无法证明来源的配置/记录隔离归档。旧业务表仅清理明确 `create_by=demo`、已知预置设备投影及显式演示兼容记录。同步旧 `admin_ledger` 快照，清理引用已归档实体的幂等响应，避免旧入口重新暴露样例。

## 切换与回滚

```powershell
python local-dev/wearable-business-release.py release <已验收目录> --admin-token-file <私密管理员会话文件>
python local-dev/wearable-business-release.py rollback <已发布目录> --admin-token-file <私密管理员会话文件>
```

上述两个命令会改变日常服务，只在实施负责人发出部署信号后运行。会话文件仅含现有系统管理员登录取得的 `X-Wearable-Token`，不要把 token 放在命令行或提交到代码库。工具调用 `GET/POST /api/admin/v1/maintenance`，不直接修改控制表绕过进程全局锁。

`release` 可另传 `--portal-token-file <私密前台会话文件>`，用于首次打开媒体业务存储。该会话必须来自前台正常登录，不能复用后台 audience 的 token。未提供时，仅在媒体存储尚未初始化的情况下，工具读取本机已记录的系统管理员登录资料，通过 `http://127.0.0.1:18084` 正常登录；不向远程地址登录，不跟随重定向，不打印或保存密码/token。

发布分两阶段，使用已通过隔离验证的镜像摘要。第一阶段只做兼容升级：停止原写者后重新备份当前库和状态，原数据全量导入新存储，启动新版本，不清理任何记录。这是正常发布唯一一次服务重启，设备随后重连。

健康检查通过不代表延迟加载的业务存储已初始化。新版本保持 `ACTIVE` 时，工具按需读取后台设备列表，随后读取停机备份中已有的媒体通话；没有通话时仅查询固定的不存在编号并要求返回 404。这些读取不会下发设备命令、开流、配置媒体或调用远端登录。必须检查 `wearable_business_meta` 中 `guardian`、`media` 两个命名空间均已初始化，保存 `cutover/storage-initialized.json` 后才允许进入 `PAUSED` 和 SQL 导出。初始化失败时停在当前兼容版本，不开始清理。

第二阶段在线调用 `PAUSED`：人工写入和业务投影停止，设备连接保持，收到的原始报文仍先持久化再确认。获取一致 SQL 导出、归档并精确清理；`WearableBusinessImport` 对 guardian/media revision 做 CAS，维护锁内允许原始报文水位增长但不改写原始接收日志。完成后调用 `ACTIVE` 重载缓存并重放，核对清理结束水位之前的报文全部处理成功。失败保留维护暂停状态和完整证据，不自动用旧快照覆盖。

回滚不把早先 dump 覆盖到已接收新报文的数据库。工具先让当前 SQL 版本重放积压报文，再停止写者，使用 `WearableBusinessExport` 从当前 SQL 的一致事务快照导出兼容 JSON、媒体凭据和报文水位，确认没有未处理报文，然后以最新导出启动旧镜像。如果停服时仍有未处理报文或导出失败，工具拒绝旧版本启动，自动重启当前 SQL 版本并恢复重放，保留证据供检查。新增 SQL 表和原始接收日志全部保留。所有版本继续携带同一 `MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY`。

旧镜像还必须先在隔离副本确认不会把清空的业务集合重新填入种子数据，验收证据 `legacy-rollback-acceptance.json` 须含 `passed=true`、`emptyCollectionsPreserved=true` 及匹配的旧 `imageId`。没有这项证据时，工具在停止当前服务之前拒绝启动旧镜像；故障恢复应继续使用持久化兼容的新版本。不能凭修改 JSON 标记跳过实际验收。

旧镜像运行期间数据权威标记为 `legacy-file`；再次升级必须由本工具读取最新兼容文件并对 guardian/media 执行受控导入，不能直接启动一个忽略旧文件的 SQL 版本。故障时保留新旧容器、当前数据库和证据，禁止为了快速恢复直接启动带旧状态文件的容器。

云端媒体文件不会被本工具删除或替换；备份包含本机文件、云资产索引和引用，未声称复制全部云端媒体内容。独立演练的网络/容器保留便于验收，清理它们时必须检查 `wearable.release` 标签和精确名称，不要使用全局 Docker prune。

## 验证

```powershell
python -m unittest discover -s local-dev -p test_wearable_business_release.py -v
```

测试覆盖真实历史与 SOS 协助保留、未知数据归档、模拟表缺失/变真/多人领用拒绝、账号密码保留、精确 ID 清理、SQL 转义、恢复行数、隔离连接参数，以及回滚使用切换后最新数据而不恢复旧 dump。运行中的数据库恢复演练以 `stage.json` 的 `restoreVerified`、`cleanupVerified` 和逐表计数为准。

## 2026-10-26 发布初始化顺序修复记录

实际发布曾在仅通过验证码健康检查后立即暂停，延迟加载的 `guardian` / `media` 存储尚无 SQL 初始化标记，导致导出拒绝。该次运行已单独恢复；本次代码修复不再执行清理，不重启或调用日常服务，也不改变归档筛选规则。

`wearable-business-release.py` 的 SHA-256：

- 修复前：`3a91fdd8cc2f83f99cbb57188c3b6abe3d553f5f18014efc3bdfd198e1e9b680`
- 修复后：`2d7ea29b202ffdc8aac083aa5562a47588ef915d53435dc6d77b0cd623ab658a`

修复增加 ACTIVE 阶段的本机业务读取和两个 SQL 初始化标记校验，初始化完成证据先于维护暂停写入。30 项无服务依赖的脚本单测通过，包含初始化顺序、已有记录/空媒体路径、拒绝未初始化或已暂停状态、现有 SQL 不重复初始化、拒绝非预期 HTTP 错误和重定向。Python 编译检查通过。此摘要只记录代码修复；后续发布仍须按新脚本哈希重新隔离演练，不得改写旧验收标记绕过检查。
