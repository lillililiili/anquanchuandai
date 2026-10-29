# 智能穿戴业务与数据清单

本次整理以两台实机和一个模拟手表为范围。具体清理计数、发布水位和镜像摘要见本机 `build/wearable-release-*/` 中的演练及发布报告；执行和恢复步骤见 [WEARABLE-BUSINESS-RELEASE.md](WEARABLE-BUSINESS-RELEASE.md)。备份含私密账号和媒体配置，不应提交或对外分发。

管理后台现保留“装备资产、人员组织、权限协作、操作日志”四个菜单，默认进入设备台账 `/admin/assets/devices`。“管理工作台”和“业务与接口”页面已移除；后台专属 `overview`、`details` 统计查询及聚合逻辑也已移除，前台综合总览和安卓业务查询不受影响。

## 设备与来源

|设备|稳定台账 ID|接入标识|来源|归属|
|---|---|---|---|---|
|安全帽|device-12|866652021714127|DIRECT_HELMET|保留未领用状态|
|安全带|device-13|866652023095053|DIRECT_BELT|保留未领用状态|
|模拟手表|RL-W001|RL-W001|DEMO_WATCH|仅保留原有单一演示人员与体征|

两台实机的上报、历史事件和定位不依赖领用才能留存。人员归属在收到报文时捕获，后续换绑不能改写历史归属。实时在线由实际连接判断；重放历史报文不创建连接。

模拟表默认显示，三端显示开关已迁到后台设备台账，通过 `wearable_business_config` 的 `simulatedWatchVisible` 统一控制三端，关闭只影响查询投影，保留底层记录。模拟体征和模拟身份明确标记，不纳入真实设备在线率和真实安全事件。

## 业务—来源—数据表—接口—页面

|业务与来源|权威数据表|主要接口|三端页面|
|---|---|---|---|
|设备、人员、组织、厂站、账号权限；管理员维护|wearable_device / person / organization / site / area / account / role|`/api/admin/v1/query`、既有台账命令|后台资产和人员；前台设备；安卓设备/人员|
|领用、归还及历史；管理员办理|wearable_assignment、wearable_assignment_history、wearable_idempotency|既有 assignments 命令；`/api/guardian/v1/mobile/assignments`|三端领用与历史|
|报文接收；直连帽/带及帽媒体回执|wearable_device_report|设备接收通道，客户端不能修改|设备状态、原始未知状态与事件来源|
|最新状态；服务端接收与连接投影|wearable_device_state、wearable_projection|`/api/guardian/v1/snapshot`、`/mobile/context`、后台查询|设备卡片、详情和地图|
|定位和轨迹；实机上报|wearable_location；保留 helmet_location_fix 原有完整帽历史|`/api/guardian/v1/locations/history`|定位、设备轨迹、安卓事件定位|
|事件/SOS、认领、观察、核验；实机与授权操作|wearable_event、wearable_event_action、wearable_event_operation、wearable_assistance；帽原始 helmet_event_link 保留|`/api/guardian/v1/events`、`/events/{id}/{action}`、`/sos`|三端事件列表、详情、处置|
|作业票；未来真实外部数据|wearable_work、external_data_record|现有 snapshot/mobile 查询|作业列表、详情；未接入为空|
|围栏、进出、分组；平台管理与有效定位|wearable_fence、wearable_fence_record、wearable_group|`POST /api/guardian/v1/business/commands`|前台围栏、分组；记录查询|
|体征；唯一模拟表|wearable_vital|snapshot/mobile 查询|模拟手表体征；帽/带不显示健康指标|
|通话、广播；服务端命令及真实回执|wearable_communication|现有通信接口，受能力与权限校验|通信列表与设备入口|
|媒体命令和元数据；帽与媒体厂家|wearable_device_command、wearable_media_asset、wearable_media_stream、wearable_media_account|现有 helmet media 接口|安全帽媒体面板；安全带无媒体入口|
|真实外部适配器响应与历史登记|external_integration、external_data_record|保留 `GET /api/admin/v1/external/integrations`、`GET /api/admin/v1/external/records`；登记 POST/PATCH 已移除|无独立接口管理页面；保留真实厂家、媒体接收记录及历史存储|
|全局功能、验收依据、维护状态|wearable_business_config、wearable_feature_acceptance、wearable_runtime_control|`/api/admin/v1/business-config`、`/maintenance`|后台设备台账的三端手表开关、设备能力与验收状态|
|迁移版本、少量扩展和审计|wearable_business_meta、wearable_business_document、wearable_business_extra、wearable_business_audit；wearable_meta/document|内部存储适配|后台审计、运维核对|
|清理归档；确认为演示及来源待核查数据|wearable_cleanup_archive 和私密备份|发布工具|不作为活跃业务展示|

业务集合按记录保存，公共关联字段和时间建立索引，`body` 保存完整业务属性，避免丢失旧字段。主数据及业务更新使用事务内增量行写入和版本比较；不再整表删除后重建。SQL 迁移脚本在 `sql/migrations/20261026_wearable_business.sql`。

Guardian 和媒体 JSON 只在首次迁移时读取，校验 SHA 并保留备份。初始化完成后由 SQL 生成读取模型，文件不再独立写业务。轨迹表保留完整历史，即使页面快照仅取近期数据。媒体二进制文件仍放原文件/对象存储；媒体账号与私密命令字段使用同一部署加密密钥保护。

## 能力与验收规则

后端对每项功能返回 `supported`、`integrationStatus`、`verificationStatus`、`verified`、`available`、`reason`，三端使用相同语义。暂时离线保留已支持入口并说明原因；缺测、过期不填补为正常值。后端也拒绝不支持或未验收的正式操作。系统管理员可显式使用验收测试路径，测试结果不自动等同于验收通过。

|能力|安全帽|安全带|模拟手表|
|---|---|---|---|
|电量、有效定位与轨迹、真实告警/SOS|保留真实链路|保留真实链路|不计真实安全业务|
|视频|已有实机视频证据；按连接可用性开放|不支持，隐藏|隐藏|
|双钩|隐藏|已验证 1=挂接、0=脱离；过期/离线为未知|隐藏|
|佩戴|按已接入状态显示；无值不补正常|待确认；未完成穿戴正反例验收|隐藏|
|拍照、录像、语音/广播|支持的入口标待联调，验收前禁用正式操作|语音待联调；拍照/视频/录像隐藏|隐藏|
|测高|隐藏|支持但验收待完成；不据此推导高低挂安全结论|隐藏|
|防双解、高低挂、近电、温度、RTK、辅助定位|按型号能力约束|未确认选配，普通业务不开放，管理端保留能力状态|隐藏|
|心率、血氧等体征|无依据，隐藏|无依据，隐藏|仅显示明确标注的模拟记录|
|外部工作票、安监、回传|未接入保持空和未接入；平台核验独立于外部结案|同左|同左|

未知告警码保留原码，不推断为具体风险。外部表保存来源、类型、外部标识、方向、原始业务内容、关联及同步结果，并按来源/类型/方向/外部标识幂等更新。工作票、人员、安监和回传本次没有新增实际外部对接；通用接口登记页面、写入口及保存验证逻辑已移除，已有真实厂家和媒体适配器仍写入独立外部记录表，历史登记与接收记录不删除。

能力来源是用户给出的 `RD-D1+智能安全帽产品说明书.pdf`、`RD-1102智能挂钩产品规格书.pdf`，结合 `output/device-ready/helmet-media-acceptance-20261026/`、`belt-acceptance-20261025/physical-stage-record.json`、`belt-sos-20261026/4g-sos-success.json` 实测证据。产品可选规格不自动等同于这两台实机已安装且已验收。

## 写入、缓存和切换约束

- `PUT /api/guardian/v1/snapshot` 返回 410。围栏/分组改为带操作标识与版本的具体业务命令；事件、领用沿用各自命令。遥测、通话结果和媒体回执由服务端更新。
- `dataVersion=wearable-clean-v1`。客户端废弃旧演示业务缓存，保留登录和必要连接配置。重新登录、断网或接口失败不能回填示例数据。
- 正式环境不启动演示种子；首次空库保持空。首次迁移存在旧文件时迁移的是原始记录，不意味着自动生成演示业务。
- PAUSED 冻结人工业务写入及后台投影，设备上报先保存原始接收日志；ACTIVE 按水位恢复。媒体回执遵循同一持久重放规则。失败报文保留待处理，不假报已成功。
- 发布前后核对设备 ID、账号数量、未领用状态、真实历史及关联、水位积压；恢复不能用旧 dump 覆盖新上报。实际发布报告应与本说明一并留存。
