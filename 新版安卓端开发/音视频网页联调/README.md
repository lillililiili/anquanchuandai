# Call Lab · 音视频与设备告警联调工具

本目录包含三种通信测试模式和一个设备告警页面。**本轮安卓与多人虚拟安全帽联调使用 `/business`，仅验证呼叫和播报回执状态，不传输音视频。** 原首页的 Agora / WebRTC 模式继续保留，可生成 **440 Hz 周期测试音**和 **640×360、15 FPS 动态测试画面**，不调用 `getUserMedia`，不依赖真实麦克风或摄像头。

网页代码在本目录（原名 `call-lab`，现为 `音视频网页联调`）。音视频、多人业务联调与告警页面共用一个 Docker Compose 服务，但身份、通话状态和验证目标不同。`/business` 需要配套开启 `CALL_LAB_ENABLED=true` 的安卓测试构建；不需要将 Java 的厂商地址切换到 Agora 测试厂商。

## 多人业务通信状态联调（本轮入口）

打开 **http://127.0.0.1:5188/business**。网页用业务账号 `admin`，安卓用同一厂站的值班账号 `siteA_duty`；密码使用当前环境实际凭据，不写入文档或截图。页面支持验证码，密码与令牌只保留在本页内存中。

**本轮通信语义更新：** `/business` 与配套安卓统一为“呼叫 / 接听”，不再区分语音呼叫和视频呼叫。接通后，值班端可单向查看安全帽画面，无需设备再次接听；网页仅反映已接通参与者的画面查看开 / 关状态，未接通者不可查看。此功能仍为单向画面状态模拟，不开启手机对端摄像头，也不代表真实视频媒体已传输。旧首页的独立 Agora / WebRTC 模式保持原语义。

**帽端只有两个按键：** “呼叫 / 接听”共用一个按钮，另一个是“挂断”。安全帽没有屏幕，不能选择联系人；空闲时按共用键自动呼叫值班人，收到来电时按共用键接听，响铃时按挂断键即拒绝。网页的人员、设备配置与普通 / SOS 注入属于管理员测试面板，不代表安全帽可操作这些菜单。当前联调以厂站**唯一在线值班账号**映射本班接听人；有多个值班账号在线时拒绝呼入并提示只保留本班账号，不按最新心跳猜选联系人。正式排班路由仍待接入。

### 安卓连接配置

本轮安卓使用 **Java 业务后端作为通信跳板**，APK 不再直连 Node `5188`：

```text
安卓 API 127.0.0.1:18084 → Java 业务鉴权 / 厂站校验 / 白名单 relay
                       → Docker 内 call-lab:18766 → 虚拟安全帽状态
```

先确认业务后端已包含 `WearCallLabBridgeController`，在项目根目录执行部署：

```powershell
docker compose -f "新版安卓端开发/音视频网页联调/compose.yaml" up -d --build
docker compose -f docker/compose.yaml -f "新版安卓端开发/音视频网页联调/backend-business-bridge.compose.yaml" up -d --no-deps backend
```

`backend-business-bridge.compose.yaml` 仅启用 `MELHAT_CALL_LAB_ENABLED=true`，将虚拟设备上游设置为 Docker 内 `http://call-lab:18766` 并接入 `wear-call-lab_default` 网络；不切换现有真实厂商 / Agora 配置。关闭跳板时在项目根目录执行 `docker compose -f docker/compose.yaml up -d --no-deps backend`，去掉该测试覆盖；无需删除业务数据库。

随后在安卓工程执行测试构建：

```powershell
flutter build apk --debug -t lib/main.dart --dart-define=API_BASE_URL=http://127.0.0.1:18084 --dart-define=CALL_LAB_ENABLED=true
adb devices
adb -s emulator-5554 reverse tcp:18084 tcp:18084
adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk
```

雷电设备序列号以 `adb devices` 实际输出为准；当前机器构建可使用 `C:\melhat-runtime\wearable-android` 工程映射路径。`127.0.0.1:18084` 是当前 APK 的 API 地址，依赖 `adb reverse` 到电脑 Java 端口；不需要反向映射 `5188`。浏览器的 `5188/business` 是虚拟设备控制台入口。安卓业务请求与 `/api/v1/lab/*` 均先到 Java，由跳板转发允许的虚拟设备操作。这个模式不需要声网凭证、音视频采集驱动或 `backend-link.compose.yaml` 的旧 Agora 覆盖；真实厂商同会话画面控制协议仍未接入。

使用业务 Bearer 与 `X-Site-Id` 请求 Java `GET /api/v1/lab/bridge-info`，应返回 `bridge=java-business-backend`、`upstreamType=virtual-helmet`、`enabled=true`、`simulation=true`、`realMedia=false`。这是跳板身份说明，不代表真实音视频已经可用。

### 联调流程

1. 网页登录并选择厂站，读取现有人员、设备及作业。勾选多台设备后点击“所选上线”，或逐台设置测试佩戴人、在线、异常并应用。模拟佩戴与异常标记只修改 Call Lab 内存，**不修改真实设备绑定、不生成普通异常事件**。页面每 2 秒续心跳，长时间操作期间也继续续期；中断连接约 25 秒后设备自动离线。
2. 安卓登录相同厂站的值班账号。网页在线值班状态出现唯一对应用户后才可设备呼入；这只是路由状态，不提供联系人下拉。具备呼叫权限但没有值班角色的管理员不作为设备呼入接收人。
3. **设备呼入一次只选 1 台在线安全帽。** 在设备卡片按“呼叫 / 接听”，或由管理员测试区注入普通 / SOS 来电。安卓应用运行期间，在应用内当前页面弹出接听 / 拒接入口；这不是操作系统后台推送，不承诺应用退出或被杀后仍可弹出。
4. SOS 会调用真实模拟事件接口，写入 `source=simulator`、`demo=true` 的测试事件。为避免来电人与事件人员不一致，SOS 的测试佩戴人必须与设备当前真实佩戴人一致；不一致时拒绝发起，**不自动修改业务绑定**。若事件已登记但设备随后离线，会明确提示事件已登记、呼叫未发起。
5. 安卓可选择多个在线安全帽发起统一群呼；网页逐台按帽端“呼叫 / 接听”键接听，按“挂断”键拒绝响铃或结束已接通会话。任一参与者离开不会直接结束仍在通话的其他人。接通后值班端可开启 / 关闭安全帽画面单向查看，安全帽被动上传、无需再确认；网页逐人反映状态。双方核对响铃、接通、拒接、结束及超时状态；此处“接通”仅指模拟信令已接受，不代表有媒体流。
6. 安卓或网页可群发文字播报，网页逐设备点击“模拟收到播报”生成回执；离线设备不能确认。**回执不代表真实扬声器播放成功**，本模式不执行 TTS 音频合成或硬件播音。
7. 网页“作业临时组”读取真实作业成员。只有点击“保存作业成员（业务数据）”才调用业务成员新增 / 移除接口；会改变项目中的实际作业成员，受原有角色和作业状态限制。它不是只存在内存的虚拟分组，页面不会自动保存或自动恢复成员。安卓刷新后可按作业筛选、群呼和群发。
8. 退出账号或切换厂站会清理当前选择并尝试让该账号控制的虚拟设备离线；网络故障时由心跳超时兜底。Call Lab 重启清除通话、模拟在线状态及播报回执，已写入的 SOS 事件和作业成员修改仍保存在业务数据库中。

详细操作及验收边界见 [联调使用说明](../开发任务拆分/验收记录/音视频通讯-20260920/联调使用说明.md)。实际雷电跨端结果由本轮独立验收记录记载，不能以网页模拟测试通过代替实机结论。

### 本轮验证

```powershell
node --test test/server.test.mjs test/business-server.test.mjs
# 已安装 Playwright 和 Chrome，必要时设置 NODE_PATH 指向该运行时的 node_modules：
node test/business-browser.mjs
```

截至本轮文档编写，**25 项服务测试通过，`business-browser.mjs` 隔离浏览器测试通过**。覆盖并发 SOS 占位、人员一致性、厂站与权限、上下线、逐参与者状态、异常失败、群播报回执及移动布局。浏览器测试使用隔离接口 fixture，不写真实业务记录，也不证明实机媒体可用。

`test/live-android-console.mjs` 是本地真实 UI 操作辅助工具，与上述隔离测试不同；会对现有演示设备设置联调状态，按命令发起真实模拟 SOS 事件。`shot 名称 [设备SN或搜索词]` 可筛选设备后截图；账号密码通过当前环境配置提供，不打印凭据。不要把它当作不写数据的自动单元测试。

`node test/live-backend-bridge.mjs` 是 Java `18084` 全路径测试：读取精确桥接标识，使用现有安全帽 `12 / 13` 验证群呼、接听、同会话单向画面启停与结束，最终离线设备；不改真实佩戴、不发 SOS。脚本只允许本机 Java 地址，不直接请求 Node，并把请求 origin / path / HTTP 状态及脱敏通话状态保存到 `artifacts/live-backend-bridge.json`。它会操作当前联调会话，请勿与同账号 / 同设备的雷电人工测试同时运行；运行结果以生成记录为准。

## 设备告警测试（无需声网凭证）

打开 **http://localhost:5188/alarms**，或者从音视频页面右上角进入“设备告警测试”。

1. 使用项目业务账号登录，选择工作厂站。这里的账号与音视频页的无密码测试身份独立。账号权限、厂站隔离、令牌有效期继续由 Java 校验；密码和令牌仅保留在页面内存中，刷新或离开页面后需重新登录。
2. 选择安全帽、安全腰带或手表，读取真实设备和当前佩戴人。如果没有设备，用设备管理员或平台管理员点击“创建 / 选择该类测试设备”。每类、每厂站复用一个 `CALL-LAB-类型-厂站ID` 设备；使用独立的虚拟型号，不为它声明真实传感器能力。
3. 选择告警、填写测试数值和可选经纬度，点击“生成告警并回读”。通过真实 `POST /api/v1/events/simulate` 写入事件，再读详情与操作记录。事件固定 `source=simulator`、`demo=true`，标识以 `call-lab:` 开头；会进入项目事件列表和既有通知链路。安卓使用同厂站账号即可查看，未分配设备的人员字段为空。
4. “重发上次事件”复用相同标识，应得到相同事件 ID、增加 repeatCount，不应新增事件或重复测试说明。网络超时后也可以重发核对。
5. 值班员认领、提交处置。SOS / 跌落 / 撞击为现有高风险类型，处置后需复核员关闭；低风险按现有处置流程关闭。页面仅开放本工具模拟事件的处置按钮，其他项目事件可读。切换账号后重新选择设备及事件继续验证。
6. “修改设备台账”可修改所选设备的资产编码，保存时提交版本号并回读验证；厂站、人员绑定、设备硬件属性不由本页随意修改。

**数据持久性：** 告警、设备台账及操作记录写入项目 MySQL，重启 Call Lab 不会清除。通话记录仍仅保存在 Call Lab 内存。测试不会伪造设备在线、电池遥测、真实佩戴或声网接通。

本地项目已有演示账号：`admin` 用于准备测试设备，`siteA_duty` 用于厂站 A 告警与处置，`siteA_reviewer` 用于高风险复核，`siteA_readonly` 用于验证只读权限。使用当前环境实际密码，文档不记录密码。不要把音视频页的 `dispatch / helmet-001` 当成业务登录账号。

### 场景和资料依据

| 设备 | 场景 | 依据 |
| --- | --- | --- |
| 安全帽（11） | SOS、跌落、撞击、脱帽、静默、低电、CPU 过温、进入禁区、离开区域、近电、登高 | 用户提供的《安全帽参数.docx》《智能安全帽1.pdf》；近电/登高标记选配 |
| 安全腰带（6） | SOS、坠落、安全钩未挂、腰带未扣、低挂高用、低电 | 联调假设，待厂商协议确认 |
| 手表（9） | SOS、跌倒、心率偏高/偏低、血氧偏低、体温偏高、离腕、低电、越界 | 联调假设，待厂商协议确认；生理数值只是测试数据 |

安全帽文档中的低于 5% 属于本地低电提示说明，本工具将其作为测试平台告警的输入，不声称现有厂商已提供该上报协议。其他预设数字不是安全阈值或医疗标准。按钮直接注入事件，不执行传感器判断、轨迹围栏运算或真实厂商回调。

平台原有事件大类不变：`sos / fall / impact / geofence / realtime`。细分场景名和数值保存在 `/events/{id}/actions` 中的 `simulate` 记录，兼容既有数据库（无需迁移）。安卓可能仍按原有大类显示标题。手表支持新增型号、设备和模拟事件；不代表手表厂商接入、任务设备规则、安卓设备筛选等全部功能已经实现。

### 后端配置与升级

继续使用 `.env` 中的 `BACKEND_URL`，默认指向本机 Docker 后端 `http://host.docker.internal:18084`。本网页不会保存数据库密码，也不直接执行 SQL。

新增接口 `GET /api/v1/events/simulation-scenarios` 返回后端唯一场景目录。模拟接口仅在**非 prod profile**且 `melhat.demo-mode=true` 或 `melhat.simulation-enabled=true` 时注册。否则页面提示接口不可用，仍可读取设备。角色权限仍需满足原有要求。

本地现有 Docker 后端升级命令（在项目根目录执行）：

```powershell
docker exec melhat-backend mvn -q -pl ruoyi-admin -am package "-Dtest=SimulationScenariosTest,EventSimulationTest" "-Dsurefire.failIfNoSpecifiedTests=false"
docker restart melhat-backend
```

原有 `backend-link.compose.yaml` 的 Agora 联调覆盖会关闭 demo-mode；现已单独启用 `MELHAT_SIMULATION_ENABLED=true`，因此测试环境可同时使用真实 Agora 凭证和模拟告警。此覆盖仅在准备进行 Agora 安卓联调时使用。

### 告警测试验证

后端测试覆盖 26 个场景默认值、参数/设备类型匹配、跨厂站拒绝、权限检查、测试说明持久化与去重。浏览器集成测试会**真实写入三个专用测试设备及三条模拟事件**，修改其中测试手表资产编码，并完成三条事件的关闭流程：

```powershell
# 使用已安装的 Playwright；此机器也可设置 NODE_PATH 为 bundled runtime 的 node_modules
node test/alarms-browser.mjs
```

可通过 `CALL_LAB_URL`、`LAB_ADMIN`、`LAB_TEST_PASSWORD` 覆盖测试连接与账号。默认使用项目本地演示账号。截图和脱敏结果保存在 `artifacts/alarms-*`。不要对正式数据环境运行该写入测试。

## 启动

在此目录执行：

```powershell
docker compose up -d --build
```

浏览器打开 **http://localhost:5188**，建议使用 Chrome 或 Edge。停止：

```powershell
docker compose down
```

端口可在 `.env` 中修改 `CALL_LAB_PORT`。默认只监听本机，音视频测试身份没有密码，不要作为正式服务公开部署。通话记录和在线状态仅保存在内存，重启后清空，不录制音视频；告警数据保存在项目数据库中。

## 三种通信模式与独立告警页面

| 模式 | 用途 | 是否需要声网配置 |
| --- | --- | --- |
| 安卓联调 · Agora | 与现有安卓 Agora SDK 互通；也支持两个网页账号互相呼叫 | 需要有效的 App ID 和 App Certificate |
| 网页自检 · WebRTC | 先测试呼叫、接听、拒接、挂断和真正的数据流传输 | 不需要，但不能直接与安卓 Agora SDK 互通 |
| 多人业务通信 · `/business` | 本轮安卓多人在线、双向呼叫、SOS、群呼与文字播报回执；只测状态 | 不需要；APK 必须开启 `CALL_LAB_ENABLED=true` |

`/alarms` 是独立的真实模拟事件写入 / 处置页面，不属于通话媒体模式。旧首页 Agora / WebRTC 的无密码测试身份与 `/business`、`/alarms` 的业务登录互不替代。下文“接现有安卓 App”专指旧 Agora 媒体链路；新状态联调按上文执行。

没有凭证时，Agora 模式会显示“安卓联调未就绪”，不会用假 Token 显示接通。网页自检的真实媒体传输也不代表 Agora 已通过验收。

## 立即测试，不需要任何密钥

1. 打开 http://localhost:5188/?account=dispatch&transport=webrtc 。
2. 选择“安全帽 001”，点击“打开所选对端窗口”。对端窗口会自动以上述身份上线。
3. 在调度员窗口点击“语音呼叫”或“视频呼叫”，到安全帽窗口点击“接听”。
4. 等待状态变为“已接通”，检查已发送/已接收字节数持续增加，视频画面的时钟及帧号持续变化。
5. 可暂停测试音、暂停测试画面、挂断；挂断后可以交换主叫/被叫，再次测试。
6. “上线 / 切换账号”会应用当前身份和 SN。一个身份、一个 SN 只允许一个在线窗口；通话期间不允许切换。

浏览器若拦截声音，点击“播放对端音频”。不需要实际扬声器也能通过接收字节和视频解码验证传输。

状态顺序：`响铃 → 正在连接 → 已接通 → 已结束`。接听按钮和接口返回都不直接标为接通；网页自检需双方 RTC 连接成功，Agora 需本端发布完成并收到远端音频。45 秒无人接听、30 秒连接失败、15 秒重连失败会结束会话。

## 接现有安卓 App

本工具有两部分：声网媒体测试端，以及与现有 `HeadbandService` 相匹配的“测试厂商”。正常链路：

```text
安卓 App → Call Lab API 转发 → 现有 Java 后端
                                  ↓ 申请厂商凭证
                              Call Lab 测试厂商
                                  ↓ 网页来电
安卓 Agora SDK ←──── Agora ────→ 网页合成音视频
```

### 1. 配置声网测试项目

如果 `.env` 不存在，将 `.env.example` 复制为 `.env`，填写：

```dotenv
AGORA_APP_ID=你的声网测试项目AppID
AGORA_APP_CERTIFICATE=该项目的AppCertificate
BACKEND_URL=http://host.docker.internal:18084
```

然后 `docker compose up -d`。Certificate 只进入 Node 服务端，不下发浏览器，不提交到 Git。网页显示“已配置”只表示格式正确；凭证是否被声网接受，需要实际通话验证。不能用随机字符串、演示 AppId 或 `demo-token` 代替。

网页安全帽和安卓分别使用同频道的不同 UID（1002 / 1001），各自签发有效期一小时的 Token。网页有 Token 续期。**现有 Java 后端的 credentials 方法只读取旧缓存，安卓长通话续期仍属于业务后端待完善项**。

### 2. 让本地 Java 后端对接这个测试厂商

先启动本工具，再从本目录执行：

```powershell
docker compose -p melhat -f ../../docker/compose.yaml -f backend-link.compose.yaml up -d --no-deps backend
```

这是一个可选的本地后端覆盖配置，会重建后端容器，使 `melhat.demo-mode=false`，把 `headband.server` 指向 `http://call-lab:18766`，并连接本工具的 Docker 网络。**只有准备进行声网联调时才运行**；无声网凭证时保持现有后端配置即可。该覆盖会将 Headband 请求指向测试工具，工具未实现的位置、TTS 等厂商能力返回不支持，不会假装成功。

结束联调后，恢复原本的后端配置：

```powershell
docker compose -p melhat -f ../../docker/compose.yaml up -d --no-deps backend
```

`melhat` 是此工作区现有 Compose 项目名。若迁移环境，请改成实际项目名。不要对业务数据库执行清理命令。

### 3. 设置测试安卓的 API 地址

为了让网页拒接、超时和挂断也结束 Java 业务会话，测试安卓应通过本工具的 API 转发访问后端：

```text
API_BASE_URL=http://127.0.0.1:5188
```

使用现有安卓项目的编译参数 `--dart-define=API_BASE_URL=http://127.0.0.1:5188`，在雷电模拟器上运行测试构建。用现有 Android SDK 的 adb 将设备端端口转回本机：

```powershell
adb devices
adb -s <雷电设备序列号> reverse tcp:5188 tcp:5188
```

本节是旧 Agora 媒体链路配置说明，不代表本轮已验证 Agora。该模式使用未开启 `CALL_LAB_ENABLED` 的构建；默认的 `10.0.2.2:18084` 不会经过 Call Lab 转发。

API 转发保留 Java 原本的登录、权限、厂站和会话逻辑，仅在创建会话后关联这次测试呼叫；网页挂断/拒接/超时后，用该次请求的登录身份结束**对应会话**。认证信息只暂存在服务内存，不出现在网页、日志或通话记录。后端结束失败会在网页提示，不声称同步成功。此转发用于通信联调，不实现原后端 WebSocket/文件服务的完整代理。

如果只把 Java 的厂商地址指向工具，而安卓仍直连旧后端，音视频可以测试，但网页拒接/挂断不能同步 Java 会话，需要安卓手动结束。推荐使用上述 API 转发。

### 4. 绑定 SN 并呼叫

1. 网页选择“安全帽 001”，设备 SN 填写后端已有设备的 SN，例如 `MH-DEMO-001`，点击上线。网页不会创建业务设备。
2. 安卓使用具有 `wear:call:start` 权限的实际业务账号登录，选择有 `intercom` 能力的这个设备；视频还需要 `video` 能力。
3. 从安卓发起呼叫，网页收到“安卓 App”来电，点击接听。安卓应收到周期测试音和动态视频。
4. 安卓挂断时工具退出频道；网页挂断/拒接时，通过上述代理更新业务会话，安卓轮询应读到结束。

**现有 Java 网关只向厂商传递 `helmetSnList`，没有传递语音/视频标志。**因此外部安卓来电在本工具统一显示音视频联调并发送合成音视频；安卓语音模式只订阅音频。内部网页互呼则严格区分语音和视频。

**旧 Agora 厂商链路不提供本轮的设备反向来电入口。** 本轮设备呼入、安卓接听 / 拒接在 `CALL_LAB_ENABLED=true` 的 `/business` 状态模式中实现，不能据此认定 Agora 反向媒体通话已打通。

## 测试接口

| 方法和路径 | 用途 |
| --- | --- |
| `GET /health` | 健康检查、在线账号和会话数量 |
| `GET /config` | 公开配置，不含 Certificate |
| `WS /signal` | 身份上线、来电、接听/拒接、状态与凭证；内部网页通话信令 |
| `GET /api/token` | Headband 测试鉴权响应 |
| `POST /api/agora/token` | 接收 `helmetSnList: [SN]`，为安卓创建测试频道并向网页发起来电 |
| `POST /api/monitor/call/end` | 接收 `channelName`，结束对应外部通话 |
| `PUT /api/intercom/end/{sn}` | 结束 SN 对应的外部通话 |
| `/api/v1/*`, `/login`, `/logout`, `/captchaImage`, `/getInfo` | 转发到 `BACKEND_URL`，保留业务鉴权 |

以下是本轮状态协议。安卓从 Java `18084` 访问 `/api/v1/lab/*`，Java 校验业务 Bearer、`X-Site-Id`、角色及允许路径后转发虚拟设备服务；Node 仍负责模拟状态，不能把其直连测试冒充经过业务后端：

| 方法和路径 | 本轮状态联调用途 |
| --- | --- |
| `GET /api/v1/lab/bridge-info`（Java） | 返回 Java 跳板身份、启用状态和虚拟上游类型 |
| `GET /api/v1/lab/roster` | 读取真实人员、设备详情、作业成员并附加模拟状态 |
| `POST /api/v1/lab/presence` | 设置单设备模拟在线、异常和测试佩戴人 |
| `GET /api/v1/lab/state?client=console` | 网页状态与设备心跳续租 |
| `GET /api/v1/lab/state` | 安卓当前账号的通话 / 播报状态、在线值班登记 |
| `POST /api/v1/lab/calls` | 设备单路呼入或安卓多设备外呼 |
| `POST /api/v1/lab/calls/{id}/accept、reject、end` | 接听、拒接、结束；网页设备操作需传 `deviceId` |
| `POST /api/v1/lab/calls/{id}/video` | 原通话内开启 / 关闭单向画面状态，不新建呼叫 |
| `POST /api/v1/lab/tts`、`POST /api/v1/lab/tts/ack` | 提交文字播报状态、逐设备模拟回执 |

作业成员仍调用 Java 原有 `POST /api/v1/work-tasks/{id}/members` 和 `DELETE /api/v1/work-tasks/{id}/members/{personId}`，属于真实业务写入。

旧 Agora 厂商接口只支持单设备呼叫；设备 SN 未上线、忙线、凭证未配置都会明确返回失败。旧测试厂商接口没有厂商级鉴权，默认只对本机开放；本轮 `/business` 使用业务账号鉴权。

## 网络与媒体

- 同机两个浏览器窗口的 WebRTC 自检不需要 STUN/TURN，也不需要访问声网。
- Agora 联调需要网络可访问声网。
- 跨设备访问网页需要 HTTPS 安全上下文；普通局域网 HTTP 地址不可作为媒体测试入口。不要为了测试修改系统或浏览器的安全选项。
- 跨网络的 WebRTC 自检可能需要 TURN，可在 `.env` 的 `ICE_SERVERS_JSON` 配置；这不影响 Agora 模式。
- Java 后端与工具通过 Docker 内部网络通信；默认容器无数据库、无录制服务。

## 验证

```powershell
npm ci
npm test
# 已安装 Playwright 和 Chrome 时：
node test/browser.mjs
```

服务测试覆盖：会话状态、双端媒体确认、离线/忙线、身份冲突、越权信令、拒接、超时、断线、厂商字段兼容、不同 UID 的凭证、安卓转发及网页拒接同步。

浏览器测试用程序生成的数据流，禁止调用真实设备采集，覆盖双端视频解码、双向语音、反向呼叫、拒接、释放轨道、断线、切换账号、390px 移动布局。报告和截图输出在 `artifacts/`。

旧媒体模式尚未完成真实 Agora 网络与安卓媒体端到端验收。服务测试中的签名用占位测试密钥，仅验证接口和 Token 格式，不表示声网鉴权通过；本轮 `/business` 状态模式的实际安卓结果另行记录。

实现依据：[Agora 自定义音视频轨道](https://api-ref.agora.io/en/video-sdk/web/4.x/interfaces/iagorartc.html)、[Agora 官方 Token 生成器](https://github.com/AgoraIO/Tools/tree/master/DynamicKey/AgoraDynamicKey)、[MDN WebRTC 信令](https://developer.mozilla.org/en-US/docs/Web/API/WebRTC_API/Signaling_and_video_calling)。
