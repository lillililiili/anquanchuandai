# 场站隔离：旧入口收口与回调接入

当前 PC 前台、PC 后台和安卓 `lib/main.dart -> wear/app.dart` 使用 Guardian/Admin 的服务端会话及场站授权。安卓默认通知分支采用带授权的 HTTP 轮询。遗留 `lib/api`、`lib/field` 中的旧调用不再是当前入口。

## 旧人用接口

后端在旧 JWT/退出处理之前将以下入口返回 HTTP 410，超级管理员旧 JWT 也不能绕过：`/hat/**`、`/ws/**`、`/test/**`、`/test2/**`、`/system/**`、`/monitor/**`、`/common/**`、`/profile/**`、`/aip/**`、`/modeler/**`、`/activiti/**`、`/todo/**`，以及旧 `/login`、`/logout`、`/register`、`/captchaImage`、`/getInfo`、`/getRouters`。

旧设备管理、未授权本地资源下载和旧角色管理不再提供兼容入口；`/tool/**` 旧代码生成器和 `/druid/**` 数据库监控也已关闭。应使用当前 `/api/admin/v1`、`/api/guardian/v1` 服务。旧 `/ws/{client}/{type}` 即使被容器直接调度也关闭连接，不再提供全量广播。

2026-11-04 已删除 31 个停用的 HTTP 控制器：11 个 `/hat/**` 控制器，以及 20 个旧账号角色、组织字典、监控、上传下载、登录验证码和测试控制器。删除前已核对当前 PC 前台、PC 后台、安卓 `lib/wear` 无这些路由调用，生产 Java 代码也无这些控制器的直接引用。两个仅覆盖被删除旧呼叫/广播控制器的测试文件随之移除；停用地址的 GET/POST 拒绝测试扩充到上述路由。

旧 WebSocket 已移除 Spring 组件和 `@ServerEndpoint` 注册，不再发布 `/ws/{client}/{type}`。类中保留原有公共字段与方法签名，供候选 JAR 与未替换类进行二进制链接；这些兼容方法不会登记或读取会话，不发送任何消息。被旧代码直接调用的连接和消息回调均以 1008 关闭连接；发送方法全部为空操作。

HTTP 边界过滤器继续为旧地址返回 410，防止旧客户端误认为还能使用这些接口。数据库表、历史记录和设备底层服务不随控制器删除。清理后的完整发布须从 `mvn clean` 构建，不能把旧 `target/classes` 或仅覆盖部分 class 的补丁包当作已删除控制器的完整版本。

设备固件入口保持原有行为：`/wsHat`、`/wsBelt`、`/api/index.php`、`/api/belt/index.php`、`/api/belt/config/index.php`，以及 `/api/melhat/index.php`、`/api/melhat/config/index.php`。其它 `/api/melhat/**` 路径停用。新 Guardian/Admin、Portal 和独立 HMAC 开放接口维持各自的认证机制。

## 遗留平台 HTTP 回调

`/ext/**` 默认关闭。现有一体帽、安全带直连 WebSocket 上报不依赖这些 HTTP 回调，不需要开启。确需接回旧平台时，由部署负责人配置独立回调身份：

| 配置 | 环境变量 | 要求 |
| --- | --- | --- |
| `melhat.legacy-callback.enabled` | `MELHAT_LEGACY_CALLBACK_ENABLED` | 显式 `true`，默认 `false` |
| `melhat.legacy-callback.key` | `MELHAT_LEGACY_CALLBACK_KEY` | 独立随机密钥，至少 32 字符；不得复用人的 token、设备凭据或写入仓库 |
| `melhat.legacy-callback.allowed-site-ids` | `MELHAT_LEGACY_CALLBACK_ALLOWED_SITE_IDS` | 该服务被授权的场站 ID，逗号分隔；空值拒绝全部设备 |

仅允许 POST `/ext/helmetAlarm`、`/ext/notifyGnss`、`/ext/sosCall`。发送方通过 HTTPS 的 `X-Melhat-Callback-Key` 请求头提交密钥，不能放进 URL。后端要求台账中已登记的 `PLATFORM` 来源 `HELMET` 设备、启用场站、非禁用/报废设备，且场站在独立回调身份的白名单中。回调不能替直连帽或安全带上报，也不能凭旧 JWT 代替回调密钥。

回调标识必须在全部台账的 `sn` 和 `portalDeviceId` 中唯一对应一条设备记录；重复标识即拒绝，包括另一个场站、已禁用设备或同场站重复记录，避免按台账顺序选错归属。

告警、定位与 SOS 继续进入业务存储和 Guardian 事件，用户读取时受场站授权限制。SOS 不再自动创建无操作者归属的旧声网频道或向所有浏览器广播频道凭据；授权值守人员通过当前人员通讯流程接听/发起会话。停用这段旧自动呼叫不会删除 SOS 事件。

回调默认关闭；代码不会生成实际密钥或自动开启回调。回调方升级需与部署配置一起验收。

## 当前业务接口

Guardian 的历史媒体、定位、围栏、体征和领用绑定按记录产生时的场站判断权限，不能仅凭人员当前所在场站放行。旧绑定只有在台账 `assignmentId` 与人员、设备身份匹配时才可追溯归属；无法确认场站的真实历史对普通账号隐藏。新绑定保存原始场站，后续人员或设备变化不改写该字段。

设备、领用、人员、账号、角色和维修操作的幂等重放重新检查当前权限与对象归属；撤销权限后不能用旧操作标识取回其他场站的结果。停用或不存在的场站不会因残留角色授权继续可见。生产新建普通角色默认没有场站授权，演示种子显式授权 `site-1`。

Guardian 的 `mobile-user` 角色额外取账号所属场站与角色授权的交集；账号未填场站时可追溯启用的关联人员，归属冲突或未知时拒绝。附加值守和管理角色仍按其显式授权管理多个场站，普通角色不会因为多个场站共用而扩大范围。

实际账号核查使用 `scripts/station-authorization-audit.py` 的脱敏只读投影。`plan-station-scope-repair.py` 只生成针对 `mobile-user` 的可审查 SQL；`deploy-station-isolation.py` 默认预检，显式应用时先停写并备份，再进行版本与内容校验后缩权。它不会修改账号凭据或其他角色，失败恢复旧容器时也不会自动放宽权限。上线证据保存在该次 build 目录的 receipt 中，不能仅以源码或种子数据判断运行状态。

## 回归

`LegacyEndpointBoundaryTest` 使用真实 Spring Security Filter 链，覆盖旧管理员 JWT、匿名、编码/尾斜杠/路径参数、相似前缀、硬件入口，以及默认关闭和显式认证回调。

`LegacyCallbackAccessTest` 覆盖无身份、越场站、无场站授权、重复标识、直连设备伪装、禁用设备和停用场站；`LegacyCallbackControllerTest` 验证 SOS 事件保留且不会发起无属主呼叫。

当前启动脚本通过 GET `/` 探测后端。`wearable-container-patch.py` 也改用该只读响应，要求 HTTP 200 且正文非空，再确认两个受保护接口的匿名请求均返回 401，不再调用旧验证码接口。可通过 `MELHAT_DOCKER_CLI` 指定 Docker 可执行文件完整路径，无需修改全局 PATH。相应测试全部模拟 Docker 和时间，不接触运行服务。
