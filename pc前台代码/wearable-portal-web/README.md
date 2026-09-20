# 智能穿戴设备平台 · PC 前台

## 账号登录更新

登录页统一使用账号、密码表单，移除身份选择和数据重置入口。保留必填校验、密码显隐、加载反馈、错误提示和安全跳转；正式模式继续使用后端认证及验证码契约。

后端未接入时，`dev:mock` / `build:mock` 的本地账号为：负责人 `admin / Admin@2026`，核验员 `verifier / Verify@2026`，查看员 `viewer / View@2026`。这些公开的开发凭据仅在本地请求提供器中校验，不是生产凭据或安全认证。上线必须使用正式构建并接入服务器认证；不得把本地身份校验当作权限安全边界。

本节取代下方旧记录中的“身份选择入口”描述，业务数据仍仅在页面内存暂存。

## 界面业务化文案（2026-09-20）

全站可见名称、提示、操作弹窗和本地视频水印已统一为业务化用语，移除顶栏场景控制入口。身份使用负责人、核验员、只读查看员；设备与业务编号使用 EQ / PERSON / WORK / EVT 前缀。登录入口明确说明认证服务未接入，顶栏保留服务状态，体征保留非实时测量说明，操作提示保留本地暂存及刷新恢复边界。

内部 mock/demo 构建名、Token 键和契约枚举保留兼容，不等于已接入生产后端。启动命令不变。详见 [界面文案验证记录](./UI-COPY-VERIFICATION.md)。

## V3 第二阶段：全站视觉推广

2026-09-20 已将样板视觉推广到七个工作区的列表、摘要、详情和公共弹窗。使用本地字体、现有图片和 SVG 图形，没有新增依赖或外部资源。统一主题位于 `src/styles/v3-workspaces.scss`，滚动规则仍由最后加载的 `workspace-layout.scss` 管理。

本次同时修正视频墙画面被压缩裁切、作业计划时间窗挤占列表、资料工具栏先于标题、装备能力区单侧空白等问题。浏览器验证范围、剩余验收项见 [V3 全站视觉推广记录](./V3-ROLLOUT-VERIFICATION.md)。不将样式覆盖等同于所有业务场景验收完成。

## 列表滚动与统一分页

列表页采用可用高度内的数据区滚动，筛选和分页保留在数据区之外。全部分页入口统一使用 `AppPagination`，保留各接口既有 pageSize。宽度不超过 1200px 或高度不足 760px 时允许正文滚动，避免高倍缩放裁掉操作。详情、总览和统计为阅读型页面，不强制塞入一屏。

实现位于 `src/styles/workspace-layout.scss`；检查范围和例外见 [列表布局验证记录](./LIST-LAYOUT-VERIFICATION.md)。这些布局修复现由 V3 第二阶段沿用。

## V3 第一阶段：炫彩工业指挥舱样板

登录、安全总览（原工作台）、人员详情已接入 V3 样板视觉。此节记录第一阶段；用户已于 2026-09-20 要求进入全站优化，最新进展见上方第二阶段。

- 开发预览：`npm run dev:mock`，访问 `http://127.0.0.1:5179`；已有服务直接刷新。
- 三个样板：`/#/login`、`/#/overview`、从人员列表进入人员详情。已登录时登录路由会按原规则恢复工作区；查看登录样板请使用用户菜单退出。
- Mock 仍只使用内存数据；正式认证、权限、统计口径与服务提供器不变。没有新增依赖或修改后端。
- 共用样板样式：`src/styles/v3-samples.scss`。人员人形图片仅在 `showcase` 展示中启用，其他紧凑体征组件保持原实现。
- [V3 验证与待确认范围](./V3-VERIFICATION.md)、[素材与生成提示词](./V3-ASSETS.md)。

## V2-7：工作台、统计分析与评审交付

Mock模式的“查询分析 → 统计报表”已开放五视图、当前快照/历史区间、同口径图表明细和本地CSV。工作台补充协同提醒与统计入口。业务仍仅存内存，刷新恢复种子；正式统计来源未接入，不会回退模拟数据。

- 启动：`npm run dev:mock` → `http://127.0.0.1:5179`，选择演示身份；已有服务无需重启。
- 历史筛选填写UTC时间，以Z结尾，范围含起点、不含终点；快照不受该范围影响。
- 领用率排除未知/冲突；显式完成取操作记录，不以提交核验、模拟回传或种子完成阶段替代。
- CSV为本机导出，不是后端报表；不要用于真实现场或生产审计。
- 152项逻辑测试、四种构建和浏览器范围见 [验证记录19](../../docs/智能穿戴设备平台/19-V2-7工作台统计与汇报交付记录.md)。
- [四条汇报演示脚本与真实接入清单](../../docs/智能穿戴设备平台/20-V2完整演示与真实接入清单.md)。下一步为领导评审，不自动开始后端建设。

本文以下V2/S阶段章节保留历史交付记录；旧S阶段“只读/九菜单”等说明不代表当前Mock模式。

## V2-6：调度协同与 SOS

运行 `npm run dev:mock`，以“演示负责人”进入“调度协同”。可选择联系人保存临时协助组、发起模拟单呼/群呼、明确推进接通/拒接/超时，以及创建广播任务和逐对象模拟回执。

- 人员、作业、事件、单路视频使用同一协同入口；一次仅一活动会话，切页保留，切厂站/退出须确认。
- 顶栏演示面板可触发合成SOS，进入独立紧急详情与原事件核验链路。结束会话不完成事件。
- 安全带电话、手表未知能力不可联系；没有真实麦克风、摄像头、RTC或设备请求。本机试听因离线能力未验证暂禁用。
- 业务只存内存，刷新恢复初始数据。核验员、只读查看员只读；正式模式不包含模拟操作。

验证、演示步骤与限制见 [V2-6 实施记录](../../docs/智能穿戴设备平台/18-V2-6调度协同与SOS实施记录.md)。

## V2-5：作业监护

Mock 模式已开放作业列表、详情、人员与监护人安排、人工检查、开始／暂停／恢复／结束监护及时间线。运行 `npm run dev:mock`，选择“演示负责人”，进入“作业监护”。

- 演示步骤：选择一号站作业1 → 安排监护人和参与人员 → 记录人工检查 → 开始 → 暂停／恢复 → 查看人员、视频或处置关联事件 → 返回并确认结束。
- 来源作业与许可只读；本地监护结束不关闭事件。设备报告、人工检查和安全许可明确分开。
- 负责人可操作；核验员、只读查看员仅查询。未保存离开需确认；切站与会话变化清理编辑。
- 参与人数、监护状态和未完成事件在人员、工作台及关联摘要同步；业务只存内存，刷新恢复种子。

137 项逻辑测试、lint、四模式构建及浏览器验证通过；详见 [V2-5 实施记录](../../docs/智能穿戴设备平台/17-V2-5作业监护实施记录.md)。真实权限、作业来源与设备能力不在本次验收范围。

## V2-4：事件处置闭环

Mock 模式已开放认领、转交、转现场核验、个人草稿、证据选择、核验版本提交、显式完成和两类模拟回执。运行 `npm run dev:mock`，以演示负责人进入“事件处置”，一号站事件1可从待认领完整演示。

- 负责人／核验员可处置；转交、阶段推进、完成及回执限当前事件负责人。只读身份仅查询。
- 提交需结论与现场情况；需处理时措施必填。提交不自动完成，“无法确认”不可完成跟进；历史核验版本及证据只读。
- 全部事件／我的待办、阶段统计和工作台同步更新。回执不代表原系统结案。
- **纯前端内存演示：切页保留、刷新恢复种子；无后端写请求，无 IndexedDB。**

131 项逻辑测试通过，专项浏览器流程、四种构建及限制详见 [V2-4 实施与验证记录](../../docs/智能穿戴设备平台/16-V2-4事件处置闭环实施记录.md)。

## V2-3：模拟视频、抓拍与录像资料

Mock模式已开放本地合成视频。运行 `npm run dev:mock`，选择“演示负责人”，进入“现场监看→视频→一号站安全帽1→单路监看”。点击播放后可演示抓拍、录像，生成后须明确保存或丢弃；保存后从“查看生成资料”进入预览/下载。

- 播放不自动开始；声音按钮有效但合成片段无音轨。画面持续标注模拟来源，真实源拍摄时间未知。
- 录像最长60秒、最大50MB，计入资料200MB总预算；不支持MediaRecorder时禁用。隐藏页面释放媒体并丢弃未保存内容，恢复需手动播放。
- 只读身份可播放合成视频，但不能采集保存或模拟隐私上报。设备实例未配置、未知、隐私开启时有明确禁用原因。
- “模拟隐私上报”仅改变内存演示状态，不控制真机。开启时停止播放与采集，关闭不自动播放。
- 资料保存设备、生成方式及本地生成时间，不推定佩戴人和拍摄时间。**刷新会清空文件和业务修改**。
- 合成素材约97KB，只进入Mock包。正式/预发布/数据库demo的媒体仍关闭；没有真实拉流、RTC或后端上传。

123项逻辑测试通过，验证范围及浏览器结果见 [V2-3实施记录](../../docs/智能穿戴设备平台/15-V2-3模拟视频与资料生成实施记录.md)。本轮仍使用frontend-design、UI/UX Pro Max与Playwright完善交互和验证，不代表真实媒体验收。

## V2-2：现场监看与本地资料

纯前端演示闭环已完成。运行 `npm run dev:mock`，打开 http://127.0.0.1:5179，选择“演示负责人”。不需要后端和密码。

- “现场监看 → 电子围栏”：绘制或坐标输入、拖动节点、撤销、保存、启停、删除和版本历史。未保存离开需确认；切站和会话变化清理草图。
- “查询分析 → 现场资料”：本地导入、预览、下载、人工关联及证据冻结；已有核验证据不可修改/删除。关联不证明历史佩戴人，不等于提交核验。
- 单文件50MB，总内存文件预算200MB；JPEG/PNG/WebP、MP4/WebM、MP3/WAV/OGG需通过类型、文件头和浏览器解码检查，不支持的编码明确拒绝。
- 位置、视频和轨迹沿用同一所选设备；不可匹配时不替换成第一台设备。围栏仅共享厂站，不推定设备关系。默认无外部底图。
- 核验员和只读查看员不能进行本阶段写操作。正式、预发布、数据库demo构建不包含该Mock操作提供器。
- **所有修改和文件只在当前页面内存中，切页保留、刷新清空。没有网络上传，没有IndexedDB持久化。** 视频墙播放、抓拍和录像留到V2-3。

117项逻辑测试、lint、四模式构建及浏览器回归通过。详见 [V2-2实施与验证记录](../../docs/智能穿戴设备平台/14-V2-2现场监看与资料实施记录.md)。UI交互参考frontend-design/UI/UX Pro Max，使用Playwright检查流程、键盘替代及两种目标分辨率。

## V2-1A：型号能力与人形体征

状态：纯前端演示基础已完成。109项逻辑测试、lint、四模式构建及开发/构建预览的39项专项浏览器检查通过；不代表真实设备或生命体征能力验收。

使用现有 `npm run dev:mock`，打开 `http://127.0.0.1:5179/#/personnel/9007199254740993101?siteId=mock-site-1`，选择演示负责人。人员详情可见蓝色人形与四类合成体征；手表装备详情复用完整面板，人员列表右侧提供紧凑摘要和详情入口。

- 模拟型号按RLD1、RLV10、RL10pro、低配版及未知轮换；文档声明、实例装配、来源接入、真机验证分开。设备详情可展开证据和禁用原因；所有真实控制保持关闭。
- 人员1-01为完整读数，1-02未领用，1-03关系未知，1-05过期，1-06源时间未知，1-07能力未知，1-08血氧缺失。顶栏演示面板选择“生命体征”可模拟未接入、失败、无权限及下次延迟。
- 体征仅是需求原型，心率/血氧/体温/血压不是已确认手表规格。不作健康诊断或生成告警；安全带锁扣等状态也不代表可靠挂点或允许作业。
- 观测保存在独立内存集合，含观测时人员/关系证据。归还转领不转移旧观测，设备历史明确显示原测量人；刷新恢复种子。没有IndexedDB或业务持久化。
- `@vitals-provider`在构建期切换：Mock调用内存处理器，正式/预发布/数据库demo返回未接入且不发HTTP体征请求。`/api/portal/v1/vitals`仅为Mock分发键，不是新后端接口。
- 新增测试：`scripts/device-profile.test.mjs`、`scripts/browser/device-profile.js`。完整验证结果及字典见 [V2-1A实施记录](../../docs/智能穿戴设备平台/13-V2-1A设备能力与生命体征实施记录.md)。

```powershell
npm run test:unit
npm run lint
npm run build:mock
# 已有5179服务时不重复启动；专用浏览器运行应用内Mock，不拦截业务网络
npx --no-install --package @playwright/cli playwright-cli -s=v21a open http://127.0.0.1:5179
npx --no-install --package @playwright/cli playwright-cli -s=v21a run-code --filename scripts/browser/device-profile.js
```

## V2-1：人员装备模拟领用归还

运行 `npm run dev:mock`，访问 http://127.0.0.1:5179/#/equipment，选择“演示负责人”。核验员与只读查看员只能查询。七个一级菜单不变，“人员装备”下现已开放当班人员与装备查询。

- 装备列表支持厂站、关键词、类型、领用状态与分页；装备详情可返回原筛选。
- 从人员列表右侧摘要、人员详情或装备列表/详情，使用同一套模拟领用归还弹窗。未提交选择离开前确认；冲突需要重新读取，不能强制换绑。
- 关系未知/冲突禁止操作；离线、通信未知、数据过期只提醒，不阻止台账操作。带表厂家协议仍待确认。
- 人员与设备主数据、当前关系、不可变历史分开保存。操作采用事务副本、版本和幂等标识，提交后刷新人员、装备、历史、视频当前关联与工作台。过去事件/资料/轨迹不重新归属。
- 一号站演示：人员 1-02 领用安全帽 → 数量 68 变 69 → 装备详情归还 → 数量恢复 68，历史新增两条。刷新恢复种子，切页保留。
- `@equipment-provider` 与 `@mock-assignment` 由构建期选择；正式、预发布和数据库 demo 不包含新增 Mock 写实现，也不请求新增装备后端端点。原数据库 demo 领用组件保留。
- 核心文件：`mock/assignment-model.js`、`mock/equipment-service.js`、`api/equipment.js`、`mock/AssignmentDialog.vue`、`views/equipment`。测试：`scripts/equipment.test.mjs`、`scripts/browser/equipment.js`。

这里只保证单页面纯前端演示一致性，不代表服务端权限、并发、真实设备或生产验收。

## V2-0：七个工作入口与基础工作台

继续使用 `npm run dev:mock`（127.0.0.1:5179）。首页 `/overview` 现在显示当班人数、明确已领用装备数、未完成事件及本人待办，点击卡片打开同口径分页明细。未完成只包含待认领、处理中和待现场核验；未知阶段单列。只读身份待办显示无处置权限。

- 七菜单：安全总览、现场监看、人员装备、作业监护、事件处置、调度协同、查询分析。
- `router/menus.js` 中 `portalPages` 保留九个原页面注册，`portalMenus` 只管理入口；原视频、定位、统计和各详情地址仍可直接访问。
- 现场监看页内切换位置/视频/轨迹/围栏；人员装备切换当班人员/装备查询；查询分析切换资料/统计。
- `utils/workspace-navigation.js` 只携带合法厂站和同站设备；`store/workspace.js` 保存临时监看选择与业务修订通知，不保存实体副本。切厂站、退出清理选择。
- `mock/workbench.js` 从现有种子计算概况，不硬编码指标。身份负责人字段与业务人员 ID 分离，不推定穿戴人即负责人。
- `@workbench-provider` 构建期选择提供器；正式/预发布/数据库 demo 均保持工作台未接入，不调用未约定接口，不回退 Mock。
- 新增 `scripts/workbench.test.mjs` 与 `scripts/browser/workbench.js`；完整只读回归继续使用 `scripts/browser/mock.js`，内存专项使用 `mock-memory.js`。

V2-0 原始范围仅含导航与工作台；V2-1新增模拟领用归还，V2-2新增围栏编辑与本地文件导入。真实上传、核验写入、视频墙播放或通信仍未开放。详情跳转和概况不是新增真实后端接口。

## 纯前端 Mock 演示（FE0）

运行 `npm run dev:mock`，打开 http://127.0.0.1:5179，选择演示身份即可进入，无需密码或后端。
`npm run build:mock` 输出 `dist-mock`；`npm run preview:mock` 在 5180 预览。

- 使用统一 Mock 内存数据和 Pinia 页面状态，不使用 IndexedDB、localStorage 保存业务数据。
- 页面内切换菜单、筛选和详情，共享同一份数据；刷新或重新打开页面恢复初始数据和正常场景。
- 仅模拟登录使用独立 sessionStorage 键，刷新仍可保持身份；这不是真实认证。
- 顶栏提供场景控制和手动恢复初始数据；后者会退出模拟身份。
- 已有 IndexedDB 演示数据库不再读取或写入，也不会自动删除。旧正式/数据库演示模式和后端不变。
- FE0原始范围为只读。后续V2-1已开放模拟领用归还，V2-2已开放模拟围栏编辑与本地资料管理；定位、轨迹、视频元数据及核验记录仍只读，事件资料引用仅为模拟冻结。
- `npm run test:unit`、`npm run lint` 验证逻辑与规范；浏览器脚本位于 `scripts/browser/mock*.js`。

独立 PC 前台，正式模式与原 PC 管理端、安卓端共用现有后端。现有 S1–S4 页面提供人员、空间资料、视频元数据和事件只读基础；作业监护、调度协同、统计业务仍占位。V2 阶段优先完善纯前端 Mock，不改动后端、数据库及设备配置；正式模式缺少主数据时显示未接入，不自动填充示例人员。

## 启动

在本目录使用 Node.js 18.18+（已在 Node.js 22.19.0 / npm 10.9.3 验证）：

```powershell
npm ci
npm run dev
```

打开 <http://localhost:5176>。严格端口模式下，端口被占用会直接报错，不会悄悄切换。旧 PC 使用自己的目录和端口 5175 启动，互不依赖。

```powershell
npm run lint
npm run build:prod
npm run build:stage
npm run preview
node --test scripts/portal-contract.test.mjs
```

`preview` 使用严格端口 5177，预览最近一次构建。开发服务、预览服务只监听本机；请勿直接用它们对外提供生产服务。

## 环境与部署

| 配置 | 用途 |
| --- | --- |
| `VITE_APP_TITLE` | 平台名称 |
| `VITE_APP_BASE_API` | 开发 `/dev-api`、生产 `/prod-api`、预发布 `/stage-api` |
| `VITE_API_PROXY_TARGET` | 仅开发代理，默认 `http://127.0.0.1:18084` |
| `VITE_ADMIN_URL` | 管理中心 HTTP(S) 地址，开发默认 `http://localhost:5175`；生产与预发布默认留空、禁用入口 |
| `VITE_BASE_PATH` | 静态资源和 hash 路由基础目录，默认 `/`，子目录部署如 `/portal/` |

本机差异放入 `.env.development.local`、`.env.production.local` 等忽略文件。`VITE_*` 会进入客户端构建产物，**不得放密码、私钥或服务端密钥**。修改后重启开发服务或重新构建。

开发代理会把 `/dev-api/login` 转发为 `http://127.0.0.1:18084/login`。生产与预发布需要由网关配置对应 API 前缀，Vite 开发代理不进入构建产物。`npm run preview` 也不代理 API，因此生产预览默认可检查静态资源，真实认证需要配置同源网关或另行提供允许跨域的 API。

生产部署示例（Nginx，`dist` 内容放到 `/srv/wearable-portal`）：

```nginx
server {
    listen 443 ssl;
    # 配置实际域名及证书。
    root /srv/wearable-portal;
    location / { try_files $uri $uri/ /index.html; }
    location /prod-api/ {
        proxy_pass http://127.0.0.1:18084/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

本轮沿用 Vue 3.5.12、Router 4.1.4、Pinia 2.0.22、Element Plus 2.2.27、Axios 0.27.2、Sass 1.56.1，Vite 固定 5.4.21。`@vue/compiler-sfc` 与 Vue 同为 3.5.12。核心版本兼容优先，不应对旧工程执行升级。

**上线前安全项**：`npm audit --omit=dev --registry=https://registry.npmjs.org` 报告 Axios（high）及 Element Plus（moderate）两个依赖告警。本轮按确认的版本要求保留，未执行 `audit fix`；需另行评估具体调用场景、升级并回归。此框架不能视为已经完成生产安全验收。

## 目录与业务接入

```text
src/
  api/auth.js                 原后端四个认证接口
  api/portal.js               S1四个只读业务接口及响应校验
  assets/images/              登录背景等静态资源
  components/                 品牌文字、图标、面板、空状态和占位页
  layouts/PortalLayout.vue    顶栏、可折叠侧栏、管理中心入口
  router/menus.js             九个静态菜单和懒加载页面
  router/index.js             hash 路由、守卫、安全返回地址
  store/user.js               当前会话、用户、角色、权限
  store/context.js            授权厂站、来源可用性与会话清理
  composables/usePortalQuery.js 取消请求、查询状态与竞态防护
  components/personnel/       人员、装备、状态与关联分区
  views/personnel/            F07列表、F03独立详情
  styles/personnel.scss       人员页面布局
  styles/index.scss          深蓝主题与响应式布局
  utils/                      Token、请求封装、权限工具
  views/                      九个业务页面、登录、401/404
```

后续在对应 `views/<模块>` 中替换占位内容，在 `api/<模块>.js` 中封装真实接口，沿用 `PortalPanel`、`ConstructionEmpty` 及请求封装。人员装备后续统一关联智能安全帽、安全带、手表，不在前台重新定义后端主键。

九个入口依次为综合总览、人员与装备、作业监护、视频监看、调度通信、定位与轨迹、告警与核验、现场资料、统计追溯。定位标签通过 `#/location?tab=live|tracks|fences` 保留刷新状态。厂站选择依赖授权context；来源未接入时禁用，读取失败时可重试。

## 登录契约与边界

- `POST /login` 请求 `{ username, password, code, uuid }`，成功读取 `{ code: 200, token }`。
- `GET /captchaImage` 支持 `captchaEnabled: false`；开启时读取 `img`（Base64 JPEG）与 `uuid`。失败可重试，登录失败后重新获取验证码。
- `GET /getInfo` 读取 `user`、`roles`、`permissions`，空角色数组也是合法已初始化状态。
- `POST /logout` 请求服务端退出，无论成功与否均清除本地会话；无法确认服务端退出时有提示。
- 使用独立 sessionStorage 键 **`Wearable-Portal-Token`**，随请求携带 `Authorization: Bearer ...`，不读写原后台 `Admin-Token`。
- 刷新后重新读取用户信息；登录恢复九个主页面及合法人员详情。人员列表和详情返回地址只保留允许的筛选参数，拒绝外部 URL、未知页面及登录循环。
- HTTP 401 和业务 `code: 401` 都按会话失效处理，同一会话只提示、跳转一次。请求失败不会转成假成功。
- 401 展示页供后续权限路由使用；认证失效直接回登录页。未知页面为 404。
- 当前静态菜单不请求若依动态菜单，不要求尚未建设的 `portal:access`。`hasRole`、`hasPermission` 只供后续界面判断，不能代替后端权限和厂站数据范围校验。
- 管理中心只打开配置的地址，不附带 Token、不跨端免登。配置入口不代表授予后台权限。
- 没有内置账号、默认密码、登录绕过或生产模拟模式。账号创建继续暂缓；真实账号须由有权限的管理员授权。

## 视觉范围

按前台 PDF 的深蓝背景、青色分隔、左侧九菜单和 F14 左介绍右表单构图建立基础样式。登录背景暂复用旧 PC 的 `login-industrial-v2.webp`（在本工程保存为 `assets/images/login-industrial.webp`），并非 PDF 的电厂航拍原图；未获得独立 ROLLING 图标源文件，当前品牌使用文字，不伪造商标图案。取得正式素材后在该位置及 `BrandMark.vue` 替换，无需变更认证逻辑。

## 验证

### S2 定位、轨迹、围栏和资料

新增四类只读页面：`/#/location?tab=live`、`/#/location?tab=tracks`、`/#/location?tab=fences`、`/#/materials`。仍使用真实登录；没有新建测试账号，也没有应用内假登录。

仅新前台增加 `ol@7.5.2`（与旧 PC 已安装版本一致）。运行 `npm ci` 安装锁定依赖，`npm run dev` 启动 5176；代理仍通过 `/dev-api` 连接 18084。生产和预发布构建分别使用 `/prod-api`、`/stage-api`，部署服务器须配置对应反向代理。未部署新版后端、没有授权厂站或未接入来源时，不会自动生成位置、围栏或资料。

S2 前端扩展位置：`api/spatial.js`（只读接口），`utils/spatial-contract.js`（字段与安全路由），`composables/useS2Workspace.js`（查询与竞态），`components/spatial`（地图、来源状态、设备选择），`views/location` 与 `views/materials`（四类页面）。每个地图独立创建和释放，没有外部底图请求；真实文件访问和所有写操作未开放。

后端仍在原工程 Portal 包内，由 `PortalSpatialSource` / `PortalMaterialSource` 提供来源扩展点，默认不访问业务表、设备平台或存储。需先确认授权主数据和协议，再实现来源；本阶段没有部署/重启运行中的后端。

详见 [S2 验证记录](./S2-VERIFICATION.md) 和 [S2 接口与来源说明](../../docs/智能穿戴设备平台/05-S2定位轨迹围栏资料实施记录.md)。

```powershell
node --test scripts/portal-contract.test.mjs scripts/spatial-contract.test.mjs
npm run lint
npm run build:stage
npm run build:prod
npm run preview
# 独立测试浏览器，只拦截测试网络响应，不使用真实账号
npx --no-install --package @playwright/cli playwright-cli -s=portal-s2 open http://localhost:5176/#/login
npx --no-install --package @playwright/cli playwright-cli -s=portal-s2 --raw run-code --filename scripts/browser/spatial.js
npx --no-install --package @playwright/cli playwright-cli -s=portal-s2 close
```

测试脚本内的 synthetic 账号和坐标只供隔离验收，不能用于真实登录。生产预览验收先打开 5177 再运行同一脚本；脚本自动识别开发/生产 API 前缀。截图位于 `output/playwright/s2-*.png`，不是现场证据。若本机没有 Playwright CLI 缓存，需在测试环境单独安装，不加入应用运行依赖。

### 前序阶段记录

框架历史验证见 [验收记录](./VERIFICATION.md)，本次增量见 [S1验收记录](./S1-VERIFICATION.md)。模拟响应只在浏览器测试会话中注入，不写入业务代码。正式环境不会因后端离线自动进入前台。

`scripts/browser` 保留了本轮浏览器验收片段，可通过 Playwright CLI 执行（不属于应用依赖，不打包到生产）。先启动新前台 5176、旧 PC 5175 及生产预览 5177，然后依次执行：

```powershell
New-Item -ItemType Directory -Force output/playwright | Out-Null
npx --yes --package @playwright/cli playwright-cli -s=wearable-portal open http://localhost:5176 --headed
npx --yes --package @playwright/cli playwright-cli -s=wearable-portal run-code --filename scripts/browser/real.js
npx --yes --package @playwright/cli playwright-cli -s=wearable-portal run-code --filename scripts/browser/auth.js
npx --yes --package @playwright/cli playwright-cli -s=wearable-portal run-code --filename scripts/browser/edge.js
npx --yes --package @playwright/cli playwright-cli -s=wearable-portal run-code --filename scripts/browser/preview.js
```

`real.js` 检查本轮真实后端关闭验证码的配置；如果后端启用了验证码，请相应调整此断言。其余脚本只使用浏览器拦截响应，里面的 fixture 账号和密码**不是可用账号**。运行完 `edge.js`、`preview.js` 会解除拦截并回到真实登录页；中途失败可关闭专用测试浏览器会话清除拦截。截图输出到 Git 忽略的 `output/playwright`。

## S4 告警与现场核验

已实现 `/alarms`（F13 列表、独立统计、右侧摘要）与 `/alarms/:eventId/verification`（F12 事实、时间线、已有记录、只读核验表单）。厂站时区转换为 UTC；无时区明确使用 UTC。认领、转交、草稿、提交、证据上传和回传均未开放，不创建本地草稿。

代码入口：`src/views/alarms`、`src/components/events`、`src/api/events.js`、`src/utils/event-contract.js`、`event-route.js`。共用后端 portal 包新增 `PortalEvent*` 和 `PortalLegacyAlarmAdapter`，提供五个 GET 及默认未接入来源，不自动读取旧报警表，也未部署到当前运行后端。

```powershell
node --test scripts/portal-contract.test.mjs scripts/spatial-contract.test.mjs scripts/video-contract.test.mjs scripts/video-player.test.mjs scripts/event-contract.test.mjs
npm run lint
npm run build:stage
npm run build:prod
# 使用已有开发/预览服务，在专用浏览器运行隔离网络测试
npx --no-install --package @playwright/cli playwright-cli -s=portal-s4 open http://localhost:5176/#/login
npx --no-install --package @playwright/cli playwright-cli -s=portal-s4 --raw run-code --filename scripts/browser/events.js
npx --no-install --package @playwright/cli playwright-cli -s=portal-s4 goto http://localhost:5177/#/login
npx --no-install --package @playwright/cli playwright-cli -s=portal-s4 --raw run-code --filename scripts/browser/events.js
npx --no-install --package @playwright/cli playwright-cli -s=portal-s4 close
# 在现有后端根目录运行，无需启动后端或连接数据库
mvn -pl ruoyi-admin -am test '-Dtest=PortalEventTest,PortalVideoTest,PortalS2Test,PortalServiceTest,RealDeviceModeTest,PlatformDeviceSyncTest' '-Dsurefire.failIfNoSpecifiedTests=false' '-DfailIfNoTests=false' -q
```

正式页面仍是真实登录；测试中的账号和合成事件不能用于真实使用。没有授权来源时显示未接入。结果与未验证能力见 [S4 验证记录](./S4-VERIFICATION.md)，字段、权限、旧报警映射和接入门槛见 [S4 实施记录](../../docs/智能穿戴设备平台/07-S4告警核验实施记录.md)。

## S3 视频监看

已新增 `/video` 视频墙及 `/video/:deviceId` 单路监看，支持三种布局、元数据筛选、设备选择、30 秒轮播与安全返回恢复。播放、抓拍、录像、对讲及远程指导仍关闭；正式登录仍使用现有后端账号，不提供演示账号。

- 页面与组件：`src/views/video`、`src/components/video`；人员/空间页面和九个菜单保留。
- 请求与契约：`src/api/video.js`、`src/utils/video-contract.js`、`video-route.js`。
- 播放器：`video-player.js` 管理状态/资源，`video-adapters.js` 提供原生/FLV 适配器，`media-provider.js` 为正式关闭来源。`mpegts.js@1.8.2` 精确锁定、按需加载，无自动重连。
- 后端：共用后端 portal 包内 `PortalVideo*` 类；两个 GET 元数据接口。默认来源不查询设备平台、数据库或存储。新代码未部署到当前运行的后端。
- 真实厂站/授权来源未接入时显示未接入；合成设备、媒体只存在于独立测试脚本，不进入业务数据或生产包。

```powershell
node --test scripts/portal-contract.test.mjs scripts/spatial-contract.test.mjs scripts/video-contract.test.mjs scripts/video-player.test.mjs
npm run lint
npm run build:stage
npm run build:prod
# 已有 5176 / 5177 服务时不重复启动
npx --no-install --package @playwright/cli playwright-cli -s=portal-s3 open http://localhost:5176/#/login
npx --no-install --package @playwright/cli playwright-cli -s=portal-s3 --raw run-code --filename scripts/browser/video.js
npx --no-install --package @playwright/cli playwright-cli -s=portal-s3 --raw run-code --filename scripts/browser/video-media.js
npx --no-install --package @playwright/cli playwright-cli -s=portal-s3 goto http://localhost:5177/#/login
npx --no-install --package @playwright/cli playwright-cli -s=portal-s3 --raw run-code --filename scripts/browser/video.js
npx --no-install --package @playwright/cli playwright-cli -s=portal-s3 close
```

`video-media.js` 在开发服务中导入独立播放器模块，用本机 Canvas 生成 WebM/VP8 合成媒体验证真实画面推进；没有访问摄像头或设备。FLV 驱动生命周期经过隔离测试，但真实 FLV 编码/解码链路尚未验收。

详见 [S3 验证记录](./S3-VERIFICATION.md) 与 [S3 契约和后续接入门槛](../../docs/智能穿戴设备平台/06-S3视频监看实施记录.md)。后端隔离测试从后端根目录运行：

```powershell
mvn -pl ruoyi-admin -am test '-Dtest=PortalVideoTest,PortalS2Test,PortalServiceTest,RealDeviceModeTest,PlatformDeviceSyncTest' '-Dsurefire.failIfNoSpecifiedTests=false' '-DfailIfNoTests=false' -q
```
