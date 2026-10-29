# person-device-v2 人员设备能力与接口说明

更新日期：2026-10-27。本文用于开发交接和验收，记录人员领用设备后在各业务页使用能力的规则。`person-device-v2` 是本文的改造名称；实际缓存合同版本为 `businessConfig.dataVersion = wearable-person-v2`，前台 `runtime.requiredDataVersion` 使用相同值。后端 `WearableBusinessPolicy.config` 在读取结果中固定返回此版本，旧 SQL 配置不需要重写，也不需要清空业务数据。

本轮代码与自动化检查已完成阶段性验证，浏览器和实机结果填写到[逐页验收模板](person-device-v2逐页验收模板.md)。自动化通过不等于实机能力验收；正式能力仍由后台验收记录决定。

## 设备和能力边界

当前业务设备为安全帽 `866652021714127`、安全带 `866652023095053`、模拟手表 `RL-W001`。模拟表统一跟随 `simulatedWatchVisible`，保留为模拟体征来源，不计入真实设备在线率和安全告警。

| 能力 | 安全帽 | 安全带 | 模拟手表 |
| --- | --- | --- | --- |
| 电量、位置、告警、SOS | 按设备能力和验收状态展示 | 按设备能力和验收状态展示 | 仅模拟电量，不扩充位置或安全告警 |
| 佩戴 | 支持，按验收及真实字段展示 | 映射确认后才能作为已验收状态 | 隐藏 |
| 双钩、相对高度 | 隐藏 | 双钩须同时有验收与映射确认；相对高度待验收时显示待联调 | 隐藏 |
| 现场视频、抓拍、录像 | 分别检查能力和验收状态 | 整个视频及影像控制区隐藏 | 隐藏 |
| 语音、广播、视频通话 | 分别检查验收与接入就绪状态；本轮人员通信界面使用语音 | 语音可标为支持但待接入，禁用；不提供安全帽视频和广播操作 | 隐藏 |
| 体征 | 隐藏 | 隐藏 | 明确标记模拟数据、非实时测量 |
| 双脱钩、低挂高用、接近、温度、RTK、室内定位等选配项 | 不据此新增入口 | 选配未确认时 `supported=false`，隐藏 | 隐藏 |

此前已确认的安全帽实时视频、安全带双钩及 SOS 业务继续保留。本次不把未接入或未验收的能力自动升级为已验收。

后台每项能力返回 `supported`、`verified`、`available`、`reason`，并可附 `optional`、`integrationStatus`、`verificationStatus`。页面遵循：

1. 不支持：隐藏能力区块。仅安全带人员不出现安全帽视频区域或镜头按钮。
2. 支持但未验收：保留入口，标记待联调并禁用；已确认支持但未接入时说明待接入。
3. 支持且已验收但离线、数据过期、无权限或服务未就绪：保留状态，禁用实时操作。
4. 当前有效人员、唯一有效领用、设备有效、真实在线且状态新鲜、功能可用、权限允许同时成立，才能执行实时操作。

人员归还或换绑后，旧页面不能继续控制设备。历史影像、历史轨迹、事件核验和 SOS 接警不依赖设备当前在线；它们仍按历史记录归属及当前账号权限读取或处置。

## 人员设备上下文

前台快照和移动端上下文提供 `personEquipmentContext`，以人员前台 ID 为键。每个人包含 `personId`、`devices`、`features`、`location`。

`features[key]` 由后台挑选该人员当前领用的合适设备，并包含能力状态以及：

| 字段 | 用途 |
| --- | --- |
| `personId` | 人员前台 ID |
| `deviceId` | 设备前台 ID，通常为实际设备编号 |
| `ledgerDeviceId` | 后台设备台账主键，仅用于区分 ID 体系 |
| `assignmentId` | 当前有效领用记录 ID |
| `assignmentVersion` | 该领用记录的版本 |

前台使用 `src/lib/person-equipment.js` 的 `personFeature`、`personDevice`、`videoPeople`；提交实时操作前用 `operationContext` 提取原样上下文。客户端不自行编造领用编号或版本。缺少上下文时安全禁用，提示刷新。

后台 `PersonEquipmentContext` 在领用操作共用的锁内重新校验领用、人员启用、厂站、权限和能力。浏览器按钮状态不替代服务端校验。

## 接口合同

下列路径除注明外均以 `/api/guardian/v1` 为前缀，使用当前端自己的 `X-Wearable-Token`。文档和验收附件不保存令牌、密码、SIP 凭据或带授权参数的播放地址。

| 方法和路径 | 用途及边界 |
| --- | --- |
| `GET /snapshot` | PC 前台只读快照，响应 `{state}`，含设备能力、人员上下文和业务配置 |
| `GET /mobile/context?siteId=…` | 安卓授权范围内的页面上下文；人员设备上下文随可见人员一起过滤 |
| `GET /devices/{id}/media` | 历史媒体、设备录像查询结果及命令回执；不返回直播授权，不因读取而开启设备视频，也不作为实时能力来源 |
| `GET /helmet/media?deviceId=…` 或 `personId=…` | 已上传媒体资料，响应 `{items}`；按历史归属授权，可离线查看 |
| `POST /devices/{id}/commands` | 按能力执行设备动作；实时操作必须携带人员和领用上下文、稳定请求编号 |
| `GET /devices/{id}/live` | 使用人员领用上下文和 `viewerSessionId` 查询当前观看会话的实际播放授权；要求当前能力有效 |
| `POST /mobile/calls` | 创建人员对应的设备通话；包含领用上下文、`video` 和 `idempotencyKey` |
| `GET /mobile/calls`、`GET /mobile/calls/{id}` | 通话历史及当前通话状态；由后端限制可见范围与操作人 |
| `GET /mobile/calls/{id}/credentials`、`POST /mobile/calls/{id}/joined`、`POST /mobile/calls/{id}/end` | 原人员会话的凭据、加入及结束；本端加入不等于设备接听 |
| `GET /helmet/calls/{id}` | 核对设备侧通话状态；设备接通须有服务端确认及对应设备证据 |
| `POST /mobile/broadcast` | `recipients` 中每个接收者携带人员领用上下文；文本 1 至 200 字，最多 50 台、同厂站、禁止重复设备；受理不等于播放完成 |
| `GET /locations/people/{id}` | 人员当前位置及相关来源状态 |
| `GET /locations/history` | `personId` 和 `deviceId` 二选一，带 `from`、`to`，可带 `cursor` 和 `limit`；单次范围最多 31 天，`limit` 为 1 至 1000 |
| `POST /events/{id}/{action}`、`POST /sos` | 事件处置及手机求助；无人员关联的设备事件和设备 SOS 仍保留，不依赖语音接通 |
| `POST /business/commands` | 围栏保存、启停、归档及分组保存等具体领域操作；不允许客户端整快照覆盖服务端结果 |

设备命令基本结构如下。示例 ID 是字段说明，不可作为生产请求直接发送。

```json
{
  "personId": "人员前台ID",
  "deviceId": "设备前台ID",
  "assignmentId": "当前领用ID",
  "assignmentVersion": 1,
  "action": "start_video",
  "parameters": {},
  "idempotencyKey": "同一次操作重试保持不变",
  "viewerSessionId": "本次观看会话ID"
}
```

`start_video`、`stop_video` 与 `/live` 使用同一观看会话 ID。一个页面关闭预览只释放自己的观看租约，不结束其他观看者。开始观看仅由显式点击触发；轮询不重复开启设备。结束录像附带原始 `sourceCommandId`，清理使用原会话上下文，即使设备已经归还，也不能借此清理其他人的新会话。

抓拍/录像采用同步占用、稳定幂等键和历史回执恢复。`requesting`、`unknown`、`accepted`、`sent`、`acknowledged`、`recording`、`finalizing`、`completed` 分别显示；错误与超时保留可核查状态，不推导成功。设备内录像查询使用 `list_recordings`，上传使用 `upload_recording`；页面只允许选择设备实际返回的文件名。

设备配置 `set_config`、`configure_sip` 不在普通人员业务页面开放。显式联调仍由系统管理员和后台联调标志约束。旧的无人员上下文通讯/凭据入口不应作为新业务调用入口。

常见错误包括 `ASSIGNMENT_REQUIRED`、`ASSIGNMENT_CHANGED`、`SESSION_CONTEXT_CHANGED`、`FEATURE_UNSUPPORTED`、`FEATURE_PENDING_ACCEPTANCE`、`FEATURE_NOT_CONNECTED`、`DEVICE_OFFLINE`、`PERMISSION_DENIED`、`IDEMPOTENCY_CONFLICT`。页面显示后端原因；归属冲突先刷新，网络不确定时保留原请求编号。

## 数据归属和持久化

| 数据 | 权威来源与归属规则 |
| --- | --- |
| 人员、设备、领用、角色权限 | 后台主数据及领用台账；前台不建立第二套领用关系 |
| 原始上报 | `wearable_device_report` 持久接收，保留设备、原始内容和接收时间；未领用上报仍可记录为设备事实 |
| 当前遥测和定位 | `wearable_device_state`、`wearable_location` 等 SQL 投影；当前人员位置必须符合当前领用关系，历史轨迹按当时归属读取 |
| 告警和 SOS | `wearable_event`、事件操作、协助表；未关联人员仍保留设备号和事件，换绑不改写事发证据 |
| 媒体和指令 | `wearable_media_asset`、`wearable_device_command`、`wearable_media_stream`；保存原操作人、厂站、人员、领用上下文和回执，不随当前设备归属追改历史 |
| 作业、围栏、分组、体征 | 对应 `wearable_work`、`wearable_fence`、`wearable_fence_record`、`wearable_group`、`wearable_vital`；作业风险、现场记录必须有实际来源 |
| 能力与显示配置 | `wearable_feature_acceptance`、`wearable_business_config`；隐藏模拟表是读取视图过滤，不代表删除历史 |
| 外部系统数据 | `external_integration` 单独记录外部配置与接入状态，`external_data_record` 记录实际入站/出站数据和关联；未接入不能显示同步或回传成功 |

PC 的内存状态和本地业务缓存只用于展示，不是数据库。设备历史不等于当前人员实时能力；事件影像与当前现场视频分别展示。

## 页面实现入口

总览不再挂集中设备控制面板。人员、作业、视频、事件等页面调用统一能力查询；单路监看复用 `VideoFrame`。大屏以 Vue `Teleport` 把真实预览挂入既有视频区域，未保留生产海报回退。资料页使用 `DeviceRecordings` 承接设备内录像查询与上传。

`DeviceStrip` 按后台能力展示真实电量、佩戴、双钩和相对高度，未验收项标待联调。旧百分比围栏不再在生产地图编辑、保存或启用，可保留历史并停用/归档。

具体页面、前置条件、截图和实机回执记录见[逐页验收模板](person-device-v2逐页验收模板.md)；自动化夹具的能力与限制见[隔离夹具覆盖摘要](person-device-v2隔离夹具覆盖摘要.md)。
