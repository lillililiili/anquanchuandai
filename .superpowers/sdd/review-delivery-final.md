# 最终交付文档审查

结论：**Approved，当前未关闭 P1/P2 为 0。** 原安装可执行性 P2 已由 7013eda 单节点启动与工作区文档修正闭环，最终复审见末节。产品代码广审批准不变；容量与交付归档实物验证仍独立待完成。以下保留初审与修正历史。

## P2：安装说明缺少可执行的前置环境、初始化与单节点路径

位置：`docs/deployment/dm8-cluster-delivery.md` 安装步骤 1/4/6；`后端代码/melhat_server-dev/deploy/cluster/README.md` 准备步骤 1–3、操作段。

当前接收人按文档从 backend 根目录安装，会遇到以下确定缺口：

1. delivery 步骤 4 要求直接运行 `deploy/cluster/kylin-preflight.sh`，但未设置脚本强制的 SHARED_FILES_DIR / MELHAT_FILES_STORE_ID。部署 README 准备第 1 步还把该脚本放在第 2 步创建共享 marker 之前；该预检必然失败。应先挂载、分配权限并创建 marker，再给出完整 env 命令，或在完整配置后使用 ops check 的自动传值入口。
2. 目标主机前提只列 Docker/Compose/Python/bash，随后 `render-config.mjs` 依赖 Node；迁移 CLI 需 JDK17。应明确宿主机的 Node24.16/JDK17 前提与构建机区别，或者给出使用已交付容器运行这些工具的精确命令。相对路径也应统一从 backend 根运行 `bash deploy/cluster/clusterctl.sh ...`，不要依赖未声明 PATH 中的裸 clusterctl.sh。
3. 文档要求“先单节点验收，再第二节点加入”，但唯一 up 入口无条件启动两个 app。没有给出可实际运行的单 A Compose 启动/共享入口组合、GATEWAY_CONFIG_GENERATION 来源与停止容器 create 证据命令。只写类名的 WearableBusinessBootstrap 也不足以从 fat jar 启动 CLI，且没有合法五份空库输入的模板位置/格式指引。应补一段可照执行的生产安装序列，确保仍保留 generation、offline app、空库、marker 与全局暂停前提，而非让交付方自行绕过门禁。
4. 交付包已经提供验证过的 jar 和 images，部署 README 准备第 3 步却默认要求“构建已经测试过的后端 jar”，交付包 backend 内容主要是部署/网关而非完整后端 Maven 工程。应优先写加载包内镜像/使用已交付 jar；源码重建属于独立可选路径，不能成为默认安装阻塞。

这是一项交付安装可用性问题，不要求新增平台功能或降低运维门禁。建议用一个 backend 根目录下的命令块覆盖这些连接点，然后再窄复审。

## 完成声明与证据核对

未发现另一项需要阻塞的 P1/P2。四文档对本机开发验证、麒麟/实际NFS/物理设备/真实媒体与Android正式发布、基础设施单点和容量未完成的边界总体准确；Caddy 固定摘要需另从仓库获取的说明没有夸称完全离线交付。

本轮实际读取的非敏感证据：

- `release-image-identities.json`：后端35290a86、镜像28c045c3...、gateway fa9f741...、Android9e3b...与文档对应。
- node-fault-a/b-final.json：3201/5678ms、HTTP样本分别3/4次200、设备重连/原会话/新telemetry断言与文档相符。文档已明确有限采样而非零错误SLA。
- dependency-fault-redis/database/files-final.json：Redis和数据库 snapshot/upload 503；缺files marker时ready503、snapshot200且有state、upload400；均pass=true。文档没有把只读查询也描述为必须失败。
- application-readback-final-correctness.json：443+2+423=868 receipts、pending全0、442定位、alarm/link各1、event2、ACK2、file publication5，与验收文档一致。
- pc-final-commit-readback.txt：真实提交并reload后已核验标题、表单值、两张1028×908图片解码、提交按钮0；支持该记录的最终读回，不据此推断未读的所有浏览器场景。
- report-android-final.md 最后两轮：9e3b安装/登录/安全存储持久化、离线设备诚实状态、事件和双照片、仅一次明确标注模拟SOS、通讯权限边界与member无轨迹入口，都与文档范围相符。旧14fc失败和六项resolved缓存差异仍披露，没有将debug说成release。
- report-migration-release-final.md 与此前独立读取的 verification-summary：最终jar两包99/28/4、91恢复表27行/8归档表、三次COMPLETE；旧71ab kill/高水位/tamper矩阵没有冒称在最终jar重跑。容量基线99/12246/5、91恢复表2731行与摘要一致，仅作为同起点快照，不是容量结果。

小范围编辑建议（非额外P2）：验收记录尾部“最终迁移时约2.15GB”与最终release迁移报告记录最高2.686GiB/89.54%口径不同，应写明具体观察阶段或删除该近似值，避免混淆迁移峰值与重启后的缓存占用。

## 本审查的边界

尚未生成并逐项核验最终交付包及其manifest，所以本次不能批准“归档内容确实无private或厂商二进制”这一打包事实；当前只能认可预定排除范围。包完成后需以真实清单及文件hash校验为准。本文也不要求容量等待期间提前填结果；最终容量结论须另有实际测量。

## 7013eda 与安装文档修正最终复审：Approved

**最终决定：交付文档与本轮 ops 窄变更 Approved，原安装可执行性 P2 CLOSED；本审查当前未关闭 P1/P2 为 0。** 前文保留初审发现，本节取代“需修正”阶段结论。被审 ops 提交为 `7013edaf1bdb381d5453404a1f79cd0cac0f4eeb`，文档为本次工作区版本；未运行 DB、Docker、Maven、构建或负载。

- `up --node a/b` 两阶段都使用 `--no-deps` 与明确服务列表：先仅所选 app，后仅所选 helmet/belt 加四个共享入口。对端停止不会被依赖拉起；对端已经运行也不会被主动停止。无 --node 时保持原先两 app 后整个项目行为。
- `generation_window()`、preflight、目标/共享入口必需、运行对端标签与挂载核验继续保留；停止对端旧 generation 的维护窗防护未放松。11 项无 Docker 测试的源码逐项检查与实现报告一致，仅按报告引用通过，未冒称真实首次单节点 Docker 启动已验证。该实际验证由后续容量 single 首次启动承担。
- README 已将共享挂载/权限/marker 放在 preflight 之前，列明宿主 Node24.16/JDK17，优先加载已交付镜像，并给出 backend 根目录下 bash 完整路径及 SHARED_FILES_DIR/MELHAT_FILES_STORE_ID。
- 首次新目标命令从已校验 manifest 读取 GATEWAY_CONFIG_GENERATION，同项目参数 create --no-deps 两个未启动 app，保留 offline 身份；显式 migrate 后初始化或完整导入，再单节点 up，验收后默认 up 加入第二节点。未建议用单节点排空代替全局停写或跳过迁移门禁。
- BOOTSTRAP.md 五份 JSON 骨架已与 GuardianValidator、AdminLedgerStore.initializeEmpty、WearableBusinessBootstrap 及 system 权限 ID 对照。账号BCrypt必须现场提供，不生成默认密码；设备/绑定为空、media空对象、acceptance空数组、业务配置布尔值与现有门槛一致。容器命令实际使用 migrate服务环境+单独java entrypoint+PropertiesLauncher和绝对/ bootstrap参数，并将只读私有目录挂载给当前操作员UID，没有把口令放argv。
- delivery.md 的步骤1/4/6已同步 Node/JDK、准确路径/env、created offline证明、BOOTSTRAP与真正的 up --node a，再双节点顺序。

保留两个非阻断编辑建议：README日志段还应将“up先等待两个应用健康”明确为“所选应用（默认两节点）”；验收记录2.15GB与release报告2.686GiB应说明观察阶段或移除近似值。它们不改变已验证架构或构成新的代码缺陷。

**边界不变：** 以上是源码/文档与已有证据的一致性审查，不是实际麒麟安装或新ops真实启动证明。最终归档尚需按真实manifest核验内容和排除项；容量未完成就继续标待验收，不以本批准代替测量。真实麒麟、NFS、物理设备、媒体及Android正式发布仍是外部门槛。


## 待执行 assemble-delivery.py 静态核验

本轮只读取 `output/dm8-cluster/assemble-delivery.py`、关联Dockerfile、tracked文件列表与依赖入口，没有导入/运行脚本，没有复制、打包、Docker/DB或构建操作。**打包脚本有1项P2需修正：输出校验器漏检子目录同名manifest文件。** 产品与文档原批准结论不因此重开。

VERIFY 内 actual 集合以 `p.name != 'release-manifest.json'` 过滤，排除了任意层级的同名文件。若解压目录新增 `extra/release-manifest.json`，该未列入清单文件不进入 actual，校验仍可打印全部通过，与“Unexpected or missing files”保证不符。应仅排除根目录的唯一manifest路径，保留子目录同名文件参与集合比较；清单自身的重复路径也宜明确拒绝。此问题无需运行真实打包即可由代码确定。

其余已核对：

- 脚本位于 W/output/dm8-cluster 下，parents[2]得到正确工作树；所有git命令指定cwd=W。先要求精确HEAD和tracked内容冻结，不把stat-only lock变化当作产品差异。最终文档需提交后再装配，否则仅tracked allowlist不会收录未tracked的BOOTSTRAP等文件。
- backend gateway allowlist覆盖gateway.Dockerfile全部COPY的protocol/device/belt根mjs及package锁、wear/fuda gateway、helmet-media auth/spool。backend jar和probe也满足backend.Dockerfile所需。该方案支持已列Docker镜像重建，不等同于包含完整后端Maven工程；源变更bundle与patch另交付。
- PC全tracked目录及同级shared保留Vite alias、组件/字体/工具相对依赖，两个package-lock也会带入；没有发现遗漏的第三个外部项目构建依赖。
- 固定JAR SHA与identities比对、OCI index单一manifest digest比对，镜像存档已由父另行核验。该脚本这里只核对索引，不代替OCI每层内容或JAR内部历史配置审查；本报告不声称jar/images不含旧内置配置。
- BASE..HEAD bundle明确依赖指定base commit，manifest已有bundleRequiresBaseCommit=true；接收方需要拥有该基线，不能把增量bundle当独立完整clone。二进制patch与sourceHead均记录。
- 复制采用显式tracked类别和逐项证据，拒绝symlink/非文件/碰撞，不递归private/runs；容量只递归公开证据目录，measured要求summary存在。公开目录仍应由父按真实内容确认，路径名过滤不是秘密扫描。
- 生成逐文件size/SHA、大小写碰撞拒绝、根目录不覆盖、zip exclusive+ZIP64、压缩/存储类型、.sh执行位及ZIP CRC读回逻辑一致。最终生成后还需真实清单及少量ZIP内容核验；静态批准不等于已产生可用包。

非阻断文案：当前tracked `deploy/cluster/test/lab-media.mjs`/media-fixture.Dockerfile也会复制进backend，且source patch/bundle本身包含这些测试源码。如果交付说明仍写“不包含测试媒体替身”，应明确是“不包含实验替身运行镜像/私有配置，不作为正式媒体交付”，或调整普通backend源集合；不能同时包含源码又声称完全未包含任何替身代码。

## 打包校验器修正窄复审：P2 CLOSED

**assemble-delivery.py 审查 Approved，脚本原P2关闭；当前文档/脚本审查无未关闭P1/P2。** actual集合现在只排除 `root/'release-manifest.json'`，子目录同名文件仍参与严格清单比较；casefold重复路径、反斜线与冒号路径明确拒绝。原缺陷没有以关闭unexpected-file检查规避。

本轮仅读取脚本，并用Python AST提取VERIFY字符串进行compile语法校验，结果PASS；没有执行装配、复制、ZIP、Docker或数据库。父任务报告临时fixture四项实际结果：正常包通过、额外子目录manifest/重复项/内容篡改均拒绝；本轮未重复执行，按父报告引用。

delivery.md已明确保留测试源码，只排除实验替身运行镜像/私有配置，并说明JAR/镜像内部历史默认配置未被该排除清单保证清理；增量bundle需要基线及verify-release使用方法也已补齐。用户已明确容量保持待验收，后续打包应使用pending，不要求新增测量、恢复或DROP操作。

最终包尚待生成，实际manifest/ZIP抽样与归档hash核验仍是后续步骤；本次脚本批准不提前代替实物核验。
