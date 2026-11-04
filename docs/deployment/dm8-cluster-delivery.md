# 达梦与双节点交付说明

本交付为开发验证版，保留单机MySQL路径，并增加DM8、双应用节点、共享文件、运维与迁移能力。源码在隔离分支 `codex/dm8-cluster-kylin-20261103`，没有合并或推送；原工作目录的页面、字体等修改未覆盖。

## 交付内容

- `backend/`：部署脚本、Compose/Caddy配置、共享目录预检、数据库迁移/备份/对账/恢复工具，以及构建协议网关所需源码。
- `backend/ruoyi-admin/target/fdc-admin.jar`：已验证的最终后端，SHA256 `35290a865fe8169bdaeeacab57151e379b7235a2808a4e7cbf0e8358158e8614`。
- `images/`：本机验证镜像的Docker存档；加载后核对 `release-manifest.json` 中的镜像ID。应用镜像使用独立运行配置，镜像标签中的lab仅为本次构建标识。
- `frontend-source/`：前台、管理端及共享UI源码与锁文件，供按现场URL构建。没有打包本机测试地址的静态产物。
- `evidence/`：经过筛选的测试摘要、构建与镜像身份、正确性/故障回读、独立审查及代码变更清单。完整私有原始证据继续保留在工作树的 `output/dm8-cluster`。
- `release-manifest.json`：逐文件长度、SHA256、源码与运行物身份。校验通过只证明文件完整，不代替现场验收。
- `source-changes.bundle`和`source-changes.patch`：隔离分支相对基线`2b6787aafaf87c5c17ba16e550ebc726d38ce2c6`的提交与补丁；bundle需要已有该基线的仓库，不能当成完整仓库镜像。可先在已有基线的独立仓库运行 `git bundle verify <绝对路径>/source-changes.bundle`，核验后再导入到独立分支，不覆盖原有工作目录。

不额外打包私有连接配置、账号口令、设备凭证、业务导出包、厂商DM8发行物/授权或测试媒体替身的运行镜像/私有配置；源码中保留相关测试用例。此清单不表示已审计并移除既有JAR或镜像内部所有历史默认配置，正式运行必须使用已核对的外置私有配置。安卓仅已验证x86_64调试包，正式签名发布及真机验收另行完成；调试包保留在本机证据目录，不作为生产安装包交付。

## 安装顺序

1. 在麒麟V10 x86_64准备Docker Engine、Compose V2、Python>=3.9、bash、NFS客户端及厂商认可的DM8版本和授权；运行配置生成需要Node24.16.0，独立迁移工具需要JDK17。安装源及RPM包由现场操作系统/厂商提供；本包不修改系统软件源，也不下载安装脚本。开发实测Docker/Compose版本记录在交付清单，不能据此推断目标麒麟版本已通过。
2. 在包根运行 `python3 verify-release.py` 核对全部文件摘要；用 `docker load -i images/backend.tar` 和 `docker load -i images/gateway.tar` 加载镜像，再核对镜像ID。Caddy须从可访问的镜像仓库获取Compose中固定的2.10.2摘要；本包不是所有基础设施齐备的离线安装盘，不允许改成浮动latest版本。
3. 准备DM8、Redis及已挂载的NAS/NFS共享根；建立最小应用权限。按 `backend/deploy/cluster/README.md` 建立私有配置、共享UUID、设备原凭证和一致的媒体/JWT密钥。应用容器UID/GID为10001；两个节点均需完成共享文件读写权限检查。
4. 从 `backend/` 按README的完整命令段设置共享路径/UUID后运行 `bash deploy/cluster/kylin-preflight.sh`，正式环境不带 `--lab`。生成配置并执行 `bash deploy/cluster/clusterctl.sh check`；新目标创建两个未启动应用容器保留离线身份证明，执行独立 `migrate`，再按BOOTSTRAP.md初始化空库或按迁移手册导入既有数据。不得以应用启动自动建表代替迁移。
5. 在构建机以Node24.16.0分别对 `frontend-source/pc前台项目` 与 `frontend-source/pc后台项目` 执行 `npm ci`、`npm run build`；管理端构建前显式设置 `VITE_ADMIN_PORTAL_URL` 为现场前台URL。保留同级 `shared/`，不要启用demo模式。两份dist部署至既有静态服务，并保持页面路由、API同源代理和权限入口。
6. 确认B组未运行后，执行 `bash deploy/cluster/clusterctl.sh up --node a` 做单节点业务核验，再执行 `bash deploy/cluster/clusterctl.sh up` 加入第二节点；验证跨节点设备/照片/会话，最后切换入口和恢复写入。脚本还提供status/logs/drain/stop/restart；备份、导入、对账和恢复见迁移README。

部署目录的README和迁移README是完整操作说明。本页不省略其中的停机、配置代次、对账或共享存储前提。麒麟预检通过只证明主机前提，仍需冷启动、重启、权限、NFS故障与真实设备业务验收。

## 迁移与回滚

执行“暂停旧端写入 → 最终导出和对账 → 空新库导入 → 单节点核验 → 加入第二节点 → 切换入口”。数据库、文件、配置与现有加密密钥必须属于同一恢复点。新端未写入时，可核对冻结点后回切旧端；新端已写入时，先暂停并完整保全新数据，再迁回空目标和验收，禁止直接恢复旧备份丢掉新增数据。

两应用节点不等于整套系统高可用。DM8、Redis、NAS、入口、wear/fuda API网关和媒体服务目前仍各自独立部署；跨主机拆分、这些依赖自身冗余及活动通话迁移不在本次完成声明内。

## 验收状态

具体结果与未完成项以同包 `evidence/dm8-cluster-acceptance.md` 为准。已完成本机真实双库往返、双节点业务与故障、PC故障反馈/恢复及所列安卓模拟器场景。容量按用户要求保留待验收，没有有效测量结果；新 `up --node` 首次真实单组启动也尚未实测，已有11项无Docker测试及独立代码审查。麒麟主机、真实NAS/NFS、物理设备、真实推送/SIP/视频和正式安卓发布仍需目标环境完成，不能承诺设备上限或扩容倍数。
