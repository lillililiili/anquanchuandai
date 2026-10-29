# person-device-v2 发布与回滚记录

日期：2026-10-27。所有精确发布时刻为 UTC；页面时间按页面标示口径显示。

## 当前完成范围

人员设备上下文、实时权限和能力校验、历史媒体与直播分离、观看会话、通话和录像归属清理、帽带定位选源，以及 PC 前台各业务页改造已落代码。两份 PC 项目已构建，日常源码服务使用当前工作区；日常后端已切换到最终新包。

云端媒体播放授权30秒补丁已由用户执行v6脚本部署，启动健康、运行身份与源码校验通过，发布前后媒体计数一致。本轮尚未完成前台逐页浏览器操作和实机闭环；不能据此宣布全部验收通过。安卓已生成 x86_64 和 ARM64 调试包并验证签名，没有安装设备。各项仍未执行的检查列在[逐页验收模板](person-device-v2逐页验收模板.md)。能力和接口边界见[能力与接口说明](person-device-v2能力与接口说明.md)。

## 发布产物

| 产物 | SHA256 / 结果 |
| --- | --- |
| 后端 `ruoyi-admin/target/fdc-admin.jar` | `B9E881B21F7A506A7AC7D237BA3225F8D45E38CC2E667FCD6525E6E09B48BB7B`，108365129 字节 |
| 新后端镜像 | `sha256:06c21065a63546a0c6d13aae9212db353cec546d478866e70fdafb9a1766d417` |
| 当前后端容器 | `ff7dbbb86db87ffe7ae0910c3408862220ab5f0bd75d811cbf27500ef9532bf7` |
| PC 前台 `dist/index.html` | `39CBDA5A092A0B0EAA260ED38E45716B610C9967D86F930C737F497A6367291D` |
| PC 后台 `dist/index.html` | `F1D0CC060DF8033B36834A23901186199AA95FFFE11A077DBBA24617DD03D182` |
| 安卓 x86_64 调试 APK | `4831C31D12BDE1C1A3DE74FA45491850AC68B88722961511580090A11F4669E0`；非通用手机安装包 |
| 安卓 ARM64 调试 APK | `3add6ff89870d49fb6b485e7189f95a4c421704b64afafc5993d4893757e418f`；仅含arm64-v8a，257744380字节 |

前端哈希只标识本轮构建入口文件，完整构建目录保留在各项目 `dist`。日常前台5191、后台5181为工作区源码服务，不将构建文件存在表述为另一个静态站点已经部署。

安卓交付副本：`android代码/melhat_android-main/build/app/outputs/flutter-apk/app-person-equipment-v2-x64-debug.apk`，原构建为同目录 `app-debug.apk`。调试证书保持原证书，SHA256 `92e7f7f2588fb97afedda6cc645e044b4610630ad9b99dca0d4e398736880461`。ARM 引擎依赖从官方地址下载时 TLS 失败，未关闭证书校验或替换不明镜像。

后续官方依赖恢复后，ARM64包单次构建成功，已保存为同目录 `app-person-equipment-v2-arm64-debug.apk` 并验证原签名；`app-debug.apk` 此时为最新构建产物，不再作为区分架构的交付链接。详细回执见 `android代码/melhat_android-main/build/person-equipment-v2-arm64-apk.json`，构建日志 `build/arm64-build-20261028T004244Z.log`。构建时间为纽约时间2026-10-27晚间，文件名使用UTC。ADB仍无设备，未安装。

## 自动化与隔离发布验证

| 范围 | 实际结果 |
| --- | --- |
| PC 前台 | 最终完整169项测试通过；其后轨迹导出的文件名和时间依据文字小改，最终构建通过 |
| PC 后台 | 477项测试及构建通过 |
| 后端 | 完整423项通过；最终定位补丁后64项定向回归通过并重新打包 |
| Node 媒体服务 | 23项通过 |
| 云端补丁脚本 | v6的46项回归、12项真实HTTP隔离检查及独立复审通过。用户已执行apply，回执为deployed，云端TTL30秒代码部署和启动校验通过；真实直播尚未验收。v5健康地址误判及恢复过程保留在后文 |
| 本地容器安全替换脚本 | 9项通过 |
| 手机访问网关 | 4项通过并经独立复审；新直播路径和领用查询参数兼容，固定上游和认证校验保留 |
| 安卓 | 真实模式70项通过；旧Mock通信12项通过、1项既有跳过；`dart analyze lib/wear`无问题 |
| 最终镜像隔离 QA | 内部网络、克隆数据库、无真实设备或云端接触；3台设备和两实机领用保持，事件/轨迹/上报未减少、待处理0，匿名后台和移动上下文均401 |

最终镜像隔离报告：`后端代码/melhat_server-dev/build/person-business-location-qa-20261027t111624z/qa-anonymous-smoke.json`。后端日志：`local-dev/person-business-full-build.log`、`local-dev/person-location-final-package.log`。完整423项和最终64项不是两个可相加的覆盖数。

## 日常后端发布与对账

发布开始 `2026-10-27T11:18:49Z`，健康检查及对账完成 `2026-10-27T11:19:17Z`。仅替换兼容后端容器，没有清理业务记录、恢复旧 SQL、修改主数据或使用应用账号凭据。

完整回执和备份目录：

`后端代码/melhat_server-dev/build/person-business-location-qa-20261027t111624z/deployment-20261027t111849z/`

其中 `receipt.json` 记录前后计数、镜像及容器身份；私有备份只供恢复，不应粘贴进聊天、公开附件或源码。备份数据库校验值：`69bcc520e0d1f0dd4bad54da868c7fb0aac4665354354faf0f7d3acfa28c9cc2`。

| 对账项 | 发布停前 | 停后 | 新服务启动后 |
| --- | ---: | ---: | ---: |
| 设备 | 3 | 3 | 3 |
| 人员 | 2 | 2 | 2 |
| 账号 / 角色 | 8 / 9 | 8 / 9 | 8 / 9 |
| 事件 | 73 | 73 | 73 |
| 统一位置记录 | 5933 | 5933 | 5933 |
| 安全帽位置记录 | 3124 | 3124 | 3124 |
| 原始上报 / 水位 | 983 | 983 | 983 |
| 待处理上报 | 0 | 0 | 0 |
| 领用表 / 领用历史 | 3 / 3 | 3 / 3 | 3 / 3 |
| 外部数据 / 来源配置 | 0 / 1 | 0 / 1 | 0 / 1 |

两实机领用签名完全一致：

- `assignment-23 | device-12 | people-19007199254740993-20 | v1`
- `assignment-26 | device-13 | people-19007199254740993-20 | v1`

人员为“设备验收人员（YS-001）”，按用户授权经正常后台办理。模拟手表及其演示人员单独保留，`watchVisible=true`。上述计数是发布检查时刻的事实，后续真实上报应持续增加。

配置原表的旧 `wearable-clean-v1` 值没有为更新缓存而整表改写；服务端读取投影统一返回 `wearable-person-v2`。前台检测版本后废弃旧业务缓存，保留登录配置。

### 发布后的持续上报和网关核查

`2026-10-27T11:26:07Z` 的 `verification.json` 记录：仍为3台设备、2名人员、73条事件，帽/带原有效领用保持；统一位置增至5972，安全帽位置3163，原始上报水位1023。切换后新增40条真实安全帽上报。总览快照读到1条正在处理的上报，随后分组查询确认这40条均已处理，不能把两个时点混写为始终无待处理。最后一次额外只读水位检查因自动审批超时未执行，不影响已取得的证据。

已恢复既有手机访问网关和原隧道。补齐 `GET /devices/{id}/live` 以及人员/领用/观看会话查询白名单，拒绝重复和非法参数；还修复既有绝对URL或双斜杠路径可能改变代理上游的问题，出站目标固定到本地后端。后端403/409保持原样传递。

网关脚本SHA256 `74bf0bc2b3384c0721ba4f9ad3156578640f274ead184dbd5b84d99cbf949d5b`。本地与公网的移动上下文、新直播路由匿名访问均返回401；公网保留TLS证书校验，检查没有发送凭据。这证明路由可达且要求登录，不代表已执行认证后的设备操作或直播验收。

## 本地回滚原则

保留兼容旧容器 `melhat-before-container-patch-20261027t111849z`，原镜像 `sha256:ba2a7df984de4ef3502d86c2ee04d3727db31bbe82f2c1213b7103d9d65e1ec6`。未执行回滚。

回滚须先确认当前容器、镜像、数据库和上报水位与发布回执一致且没有其他后续发布。停止当前新容器，保留其身份和日志，恢复前一兼容容器并仍连接**当前数据库和持久目录**；启动后重新验证健康、匿名鉴权、设备/领用签名及上报处理水位。`local-dev/wearable-container-patch.py` 的失败恢复使用此顺序。

不得把发布前 SQL dump 或旧 JSON 覆盖到当前数据；这些备份只用于灾难恢复核查。如确需从备份修复数据库，必须先保存切换后新增上报及处理水位并完成增量重放和对账，不能仅恢复旧容器就宣布恢复完成。回滚到旧应用后，新人员实时能力入口可保持禁用，历史数据必须保留。

## 云端媒体发布与历史排查

目标为现有 `39.106.212.138` 媒体服务，公开域名 `https://lingzhiaide.com`。已准备并审查：

`后端代码/melhat_server-dev/local-dev/helmet-media/cloud/patch-playback-ttl-v6.py`

当前v6脚本 SHA256：`979AABFE339FFADFC5187D8BDC9D4B963D8E6C1054B9D90FCF901341E2509910`。旧文件不再作为本次发布入口。此前v5为`0F1A7020CDFD41EB2946E745F37BDADCB9EC3B9D243E359499915A817C871FFC`，v4为 `58E9CBF2B56D50543BB39D73F7EE837018738AEAC122BCA6F40A1102E0DF2FA3`，v3为 `280EBF98D00C9F23B674A73DF4AC46B051884936DC19B5F083B943C4F9C38BB9`，命名空间修订版为 `A12E09945E8E0D09CB879A41C4DB5556ED363E300876F4BD90236792A08F8903`，初版为 `B178831C59957E2BA4FE39984D3BF2E3A8830D03956DC9F23BACDE838C99231A`。补丁仅把现有服务播放授权时长由3600秒改为30秒，发布推流授权保持不变。服务身份、配置、持久目录、源文件和镜像必须匹配才能执行；保留旧容器，回滚仍使用当前媒体状态，不恢复旧状态覆盖新增文件。进行中的平台录像须先完成。

用户已打开云管理终端。后续曾恢复浏览器控制并重新连接，已实际只读查询到 `helmet-media-control-1` / `helmet-media-control:protocol-20261026`；随后浏览器控制连接中断，电脑控制再次被自动审批审查停止，原因是无法可靠确认 Windows 当前浏览器网址。

用户已自行上传初版脚本并执行 `preview`，返回 `Unexpected namespaces`。随后用户提供定向 `docker inspect` 输出：`IPC=private CGROUP=host IMAGE=helmet-media-control:protocol-20261026`。初版对命名空间的兼容判断过窄，尚未执行任何容器变更。

命名空间修订版仅支持已核对的IPC `private` 与cgroup `private/host`，重建时显式传原值，更新后严格比较；缺失、空值和未知模式拒绝。预览显示非敏感命名空间模式及镜像标签；加入已观察到的精确镜像标签，镜像ID和源码哈希的两次校验保持。该修订版11项测试通过后，用户再次预览返回 `Unexpected masked system paths`，仍未执行容器变更。

v3取消对某个Docker版本默认系统路径集合的猜测，要求原字段是非空、规范的绝对系统路径。`apply`先创建停止状态候选，严格比较Config、HostConfig和有效挂载，任何保护路径增减均拒绝；只允许自动主机名、预期新镜像及CLI输出附着属性的派生差异。全部通过并再次确认原容器及源码未变化后，才停止旧容器、备份并按不可变ID启动同一个已核对候选。启动后再次核对ID、镜像、Running/Status及全部配置，防止按名称误认其他容器。环境使用0600私密env文件传递，不出现在Docker命令参数中。apply/rollback使用非阻塞互斥锁；候选预检失败不触碰旧服务；回滚拒绝停止身份未知的容器，继续保留当前数据。

预览现在一次汇总配置、源码和活动录像的检查问题，只输出字段名和非敏感元数据。开发时发现本地旧同名脚本被恢复为初版内容，原因未确认；因此最终交付使用独立文件 `patch-playback-ttl-v3.py`，并在测试及独立复核后确认上述哈希。26项测试覆盖预检失败、创建超时、回执写失败、配置改变、运行身份改变、成功顺序和保留新增数据的恢复。Python3.6语法检查通过。

本机实际Docker隔离验证也通过：两个临时容器始终created/Running=false，唯一原始配置差异为自动生成Hostname，保护配置全部一致；测试专门把网络设为none，未连接设备、云端或日常服务。按本次ID和状态核对后清理，空数据目录保持为空。证据：`后端代码/melhat_server-dev/build/ttl-created-probe-20261028t011559z-3699f053/result.json`。本机验证不替代云端预检。

用户已上传v3并执行聚合预览，仅返回 `Unexpected custom host identity`，源码和媒体状态没有其他预检错误；云容器未变更。原因是旧规则要求Hostname等于容器ID前12位，未兼容既有自定义/继承主机名。

v4改为验证并显式保留原Hostname和Domainname（`--hostname`及非空`--domainname`），Hostname也纳入切换前后的严格配置比较；不再把Hostname变化豁免。其他候选预检、命名空间、保护路径、源码/镜像校验、锁和恢复规则保持。29项测试通过并独立复核；本机Docker用自定义`ttl-control-legacy`/`internal.example`创建停止候选，Config/HostConfig/Mounts原始差异列表为空，测试容器全程created且已核对本次ID清理。证据：`后端代码/melhat_server-dev/build/ttl-created-probe-20261028t014240z-522b4b31/result.json`。

用户已执行v4预览并提供完整输出，预览通过。原容器为`1c92dcf199bd092778240b3728b14ee8fefc79e1d5d7020eb50dc896cb83b7af`，镜像为`sha256:e5d29a0360c321c05617d4d0307afea604f271b5f6824bb2a978fd93590f9ddf`；原源码哈希`a24b3407f0367194e124e1a85ce6233da0bc6c7a083dbab6b39ddf56e4f8833d`，目标源码哈希`bc45c253745c14909ec7ddde380454bbe6ea5febbaa30e259130fb017d799d72`。媒体状态为1份资产、22条事件、水位22、活动录像0；命名空间和路径保护维持原值。原始预览摘录保存在同目录`person-device-v2云媒体发布前预览.json`，明确为用户提供的证据。当前等待正式apply结果，尚未确认云端发布完成。

用户随后执行v4 `apply`，在停止候选预检阶段被11项HostConfig差异拒绝：BlkioDeviceReadBps、BlkioDeviceReadIOps、BlkioDeviceWriteBps、BlkioDeviceWriteIOps、BlkioWeightDevice、Devices、Dns、DnsOptions、DnsSearch、ExtraHosts、Ulimits。输出明确为原服务未停止。此阶段已构建候选镜像并创建停止候选及私密回执目录，不能描述为云端完全无新文件/容器；正式媒体服务和当前数据没有切换或恢复。

v5仅将上述11项可选列表字段的`null`和真正空列表`[]`作为“没有配置项”等价处理；非空列表、其他类型以及任何其他字段仍严格比较。没有关闭DNS、设备、限制或路径保护检查。差异提示追加值的类型/项数，不输出配置内容。完整35项测试及独立复核通过，覆盖原null/候选空列表的完整成功流程，以及候选新增真实DNS、设备映射或ulimit时在停服前拒绝。创建、身份、哈希、锁和恢复流程与v4一致；本次未再次触碰实际云容器。

用户已上传并执行v5的apply。候选通过配置预检，但启动后的健康检查硬编码为`127.0.0.1:18190`，与既有`MEDIA_LISTEN_HOST=10.255.1.1`不符。脚本停止候选并启动旧容器后，仍使用错误地址检查，因此输出“compatible recovery did not complete”。这是脚本检查错误，不能据此断定原服务实际恢复失败。

用户随后提供只读核查：原容器`1c92dcf199bd`以正式名称运行（Up 16 minutes）；候选`32d80b45def5`保留为`helmet-media-control-1-failed-20261028t020845z`且Exited (0)；此前候选`27278f07016a`仍为Created。对正确地址`http://10.255.1.1:18190/healthz`的无代理请求返回`{"status":"running"}`。确认原服务已恢复，不再重启或清理这些容器。核查未提供恢复后媒体计数，不能将健康响应当成完整数据对账。用户证据保存在`person-device-v2云媒体恢复核查.json`。

v6改为读取原容器的`MEDIA_LISTEN_HOST`和`MEDIA_PORT`，预览和最终切换前先检查原服务健康；候选启动及旧容器恢复使用同一配置地址。只探测已审核本地地址，禁代理和重定向，检查HTTP状态、JSON状态和响应大小。异常回执保留发布与恢复阶段，终端错误给出回执路径，不输出凭据或HTTP响应正文。源码的两处TTL变更和原有严格配置/身份保护保持不变。云端预览须明确显示实际地址和原服务健康结果；最新预览结果见下文。

最终v6验证：`cloud`目录执行`python -m unittest test_playback_ttl_patch.py -v`，46项全部通过。覆盖真实配置地址、合法/非法端口、原服务预检失败不创建或停止容器、候选失败后按相同地址恢复旧服务、保留当前媒体增量及失败阶段记录。独立代码复审无阻塞，Python3.6语法检查通过。另用两个临时loopback HTTP服务做实际网络验证，12项全部通过：正常响应、503、错误JSON状态、超长响应、拒绝重定向及忽略代理环境；重定向目标与代理收到0次请求。临时服务已关闭，未访问云端、日常服务或凭据。最终证据`后端代码/melhat_server-dev/build/ttl-v6-health-probe-20261028t024326z-28a92906/result.json`绑定本节v6哈希。该本地验证不代替云端预览、发布后对账及真实直播验收。

用户已上传并执行v6只读预览，完整通过：`healthUrl=http://10.255.1.1:18190/healthz`、`currentServiceHealthChecked=true`，原容器、镜像和源码哈希与上次通过的预览一致；媒体资产1、事件22、水位22、活动录像0。原始记录另存`person-device-v2云媒体v6发布前预览.json`，保留v4历史证据。随后用户按本次哈希执行apply并提供成功回执，见下节。

### v6已部署回执

完整用户来源回执保存在`person-device-v2云媒体v6发布回执.json`，`status=deployed`。批次目录时间为`2026-10-28T03:06:08Z`，对应纽约时间`2026-10-27 23:06:08`；这是脚本创建备份目录的时间，未将其当作精确发布结束时间。

| 项目 | 结果 |
| --- | --- |
| 正式容器名 | `helmet-media-control-1` |
| 新容器 / currentContainerId | `4531324372b13d4542acac0093dbc2f1476ad8094a171b37ea57c9c4815009ee` |
| 新镜像 | `sha256:a8dbf339e2e0d5c5ea79892332f59830c418484a1634a8a69eceb6248c6161b3` |
| 运行源码SHA256 | `bc45c253745c14909ec7ddde380454bbe6ea5febbaa30e259130fb017d799d72` |
| 保留旧容器名 | `helmet-media-control-1-before-20261028t030608z` |
| 保留旧容器ID / 回执containerId | `1c92dcf199bd092778240b3728b14ee8fefc79e1d5d7020eb50dc896cb83b7af` |
| 备份目录 | `/opt/helmet-wear/helmet-media/.local/playback-ttl-patch-20261028t030608z` |
| 发布前 / 后 | 资产`1 / 1`，事件`22 / 22`，水位`22 / 22`，活动录像`0 / 0` |
| 当前数据恢复 | `dataRestored=false`，使用当前媒体目录，没有用旧状态覆盖 |

核对v6成功路径后，`deployed`表示候选镜像已完成播放TTL30秒/推流TTL14400秒断言，停止候选配置核对、切换前再核对、新容器健康探测、运行ID/镜像/状态/配置及运行源码哈希检查均通过，随后写入主机源码、更新镜像标签并保存回执。`currentServiceHealthChecked`来自原服务预览；新容器健康检查成功由后续成功路径确认，不能只把这个布尔字段解读成新服务检查结果。发布前后上述计数一致，但未以此宣称每个媒体文件均已人工打开核验。

回执的`containerId`保留原服务身份，当前正式运行身份看`currentContainerId`；`candidateContainer`是候选准备阶段名称，发布后候选已改为正式名称。`failedContainer`只是脚本预留的失败恢复名称，该成功回执没有证明存在这个失败容器。旧容器继续保留；本次未执行回滚或清理。

已部署的是播放授权时长代码，尚未验证登录后的直播凭据、真实移动画面、断流恢复、退出、多页面占用和领用变化后的失效。逐页页面验收、双向语音、真实照片录像及安卓安装仍按后续验收执行，不把部署成功计为实机功能验收。

以下保留本次已执行命令供追溯，不需重复运行。已上传文件为 `/home/admin/patch-playback-ttl-v6.py`。发布前只读预览命令（也会由apply自动执行）：

```sh
sudo python3 /home/admin/patch-playback-ttl-v6.py preview
```

已核对预览的`healthUrl`为`http://10.255.1.1:18190/healthz`、`currentServiceHealthChecked`为`true`，以及镜像、源文件哈希和状态后，用户执行了：

```sh
sudo python3 /home/admin/patch-playback-ttl-v6.py apply --expected-image 'sha256:e5d29a0360c321c05617d4d0307afea604f271b5f6824bb2a978fd93590f9ddf' --expected-source 'a24b3407f0367194e124e1a85ce6233da0bc6c7a083dbab6b39ddf56e4f8833d'
```

脚本针对旧3600秒实现，部署后不应重复执行本次preview/apply。确需云端回滚时，先确认没有其他后续发布和活动录像，再使用成功回执的备份路径；下列命令仅记录恢复方式，本次未执行：

```sh
sudo python3 /home/admin/patch-playback-ttl-v6.py rollback --backup-directory '/opt/helmet-wear/helmet-media/.local/playback-ttl-patch-20261028t030608z'
```

后端继续拒绝超过45秒的播放凭据，返回 `MEDIA_SERVICE_UPGRADE_REQUIRED`，不返回授权URL、不续期观看租约。云端30秒代码现已部署，接下来验证真实业务请求拿到的凭据与播放行为；未放宽该校验。

## 后续验收顺序

云端发布回执到达后，本机Docker引擎及前后台进程未运行。已启动既有Docker Desktop，原日常后端`ff7dbbb86db8`及`melhat-mysql`、`melhat-redis`恢复运行，没有重建或恢复数据库；两端Vite在原loopback端口5191/5181恢复。最终本机网络匿名检查：前台200、后台200、后端`mobile/context`401。Chrome标签列表可读取，但接管已有前台标签和打开新前台标签均超时，尚未取得实际页面状态或直播画面，不使用其他Windows控制方式绕过此前审批限制。核查记录见`person-device-v2本地恢复核查.json`。

1. 云端v6部署及计数对账已完成；继续验证认证后的直播业务链路和实际画面。
2. 恢复前台原登录标签的浏览器控制连接，按验收模板逐页操作并留截图；当前没有本轮前台逐页截图。
3. 在真实测试人员已领用两台设备的前提下，核实在线、电量、有效定位和双钩；再按联调安排验证视频、SOS处置。
4. 语音必须双向实际听见，抓拍/录像必须取得真实文件后才能填已验收；未通过能力仍保持待联调。
5. 安装已生成的 ARM64 包并完成真实安卓设备回归。构建或接口受理不能替代实机结果。
