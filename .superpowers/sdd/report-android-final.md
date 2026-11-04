# Android 隔离 debug 构建与模拟器准备

状态：**DONE_WITH_CONCERNS：本轮隔离Android实际UI范围完成**。新9e3b8406 APK在最终35290a86后端上通过登录、凭据持久化、人员/设备、告警字段及双图解码、隔离手动SOS、可见绑定历史验证；通讯不可用原因已实际读回。member没有历史轨迹入口，该项未验证，不提升权限伪造通过。旧14fc7d7a包缺少注册文件，不接受交付。独立AVD已关闭，最新证据见末节；前文保留构建、失败和分轮历史。

- 隔离根：`D:/DevTools/wearable-cluster-android-1104`；源码副本 `app`，实际依赖缓存 `pub-cache-v2`。
- 原工作树产品源码、lock、Git index 均未修改；复制的是当时工作树当前字节，保留原有 dirty pubspec.lock。
- 已复制并哈希核对 633 个源码文件、200 hosted packages（559,412,058 字节），映射全部 210 package roots、22 Android plugins；原包树只读，未做 pub get 或依赖升级。
- `pubspec.lock` 原件/副本 SHA256：`7aa3ffece12569a13cb912393ab6dc1c7a985a5b5f63c100b65e7b777299dec9`。
- 未复制 push.properties、signing.properties、key.properties、keystore；debug 将使用空 JPush appKey，真实推送不启用。
- 新 AVD `wearable_cluster_1104`：独立 `avd`/`android-user`，API35 google_apis x86_64、Pixel 4、1536MiB、2核、2G data；尚未启动。WHPX 探测可用，ADB 初始无设备。avdmanager exit 0，存在旧/当前系统镜像 devices.xml 读取警告；config.ini 的目标 image/ABI 已读回正确，是否能开机仍待验证。

证据目录：`output/dm8-cluster/android-final/`。包含 `preparation.json`、`source-manifest.json`、`resolved-manifest.json`、`avd-preparation.json`、复制/AVD日志、构建/验证脚本、最终 APK 与下列构建证据。构建脚本只修改副本 gradle.properties，明确使用1200m heap、单 worker、Kotlin in-process/incremental=false、ASCII Java temp；实际 Gradle daemon 参数也已读回确认。

准备过程有两次可解释失败：iOS 示例 ephemeral 生成目录残留；Windows resolve 展开 Pub Cache 到 OpenAI LocalCache 后路径过长。最终排除生成目录，保留原 cache 的短路径并通过 Windows 长路径前缀只读复制/哈希。旧部分缓存 `pub-cache` 保留不用；自动审批拦截了清理该任务缓存临时生成目录的操作（`blocked by policy`），随后改用全新 `pub-cache-v2`，没有重试删除。

## 构建口径

Flutter 3.41.3 / Dart 3.11.1；debug、`--no-pub`、android-x64。构建 defines：

```text
WEAR_BACKEND_URL=http://10.0.2.2:18080/wear-api
API_BASE_URL=http://10.0.2.2:18080
WEAR_MOCK=false
WEAR_TEST_SITE_MODE=false
```

此为真实业务客户端指向本轮隔离入口。曾因内存不足等待父任务排空测试后端；收到资源释放通知后执行构建，`build-result.json` 的 exitCode=0，Gradle assembleDebug 用时514.7秒。原 Agora 路径问题已实际解除：副本产出包括 x86_64/arm64 在内的 Agora native library，最终 APK 按 app ABI 过滤为 x86_64。

## APK 与资源读回结果

- APK：`output/dm8-cluster/android-final/app-debug.apk`，ASCII 原产物也保留在 `D:/DevTools/wearable-cluster-android-1104/app/build/app/outputs/flutter-apk/app-debug.apk`。
- 大小226,036,870 bytes；两个位置 SHA256 相同：`14fc7d7a2b93ce0b17d6c47477c59e84fe8c5c0633f1f30fc26a5c279dbdd9ed`。
- aapt：`com.rolling.intelligence_headband`，versionName1.3.1/versionCode8，debuggable，minSdk24/targetSdk36，native-code仅x86_64；lib/x86_64/libflutter.so存在。
- apksigner verify 成功，证书DN为 Android Debug（非release）。debug payload包含 `http://10.0.2.2:18080/wear-api`；完整构建参数记录了双地址和两个false开关。
- packaged manifest中JPUSH_APPKEY恰好一项且值为空，push/signing配置文件不存在；未启用真实push。
- 编译后对原工作树633源码文件逐项重算hash，变化列表为空；原lock与副本lock仍一致。原目录 Git status 仍只有开始前已有的pubspec.lock dirty，本任务没有提交或修改index。
- 构建结束后按记录的PID27416及精确启动时间核对身份，只停止本任务Gradle daemon；已确认该PID退出。没有停止其他Java或任何后台服务。停止后内存读回约3780MiB空闲。
- ADB仍显示无设备；AVD未启动，没有新增运行的模拟器。待父任务完成双app验收后另行安排单app+AVD。

核验文件：`build-debug.log`、`build-result.json`、`apk-verification.json`、`apk-badging.txt`、`apk-signature.txt`、`manifest-verification.json`、`gradle-daemon.json`、`gradle-daemon-stop.json`。构建日志仍有现存SDK XML3/4版本和第三方deprecated/unchecked警告，均未导致失败；这不替代之后的安装、启动和交互验证。

## 固定依赖差异与发布边界

| 包 | debug 实际 resolved | 原 lock |
|---|---|---|
| intl | 0.20.2 | 0.20.3 |
| matcher | 0.12.18 | 0.12.20 |
| meta | 1.17.0 | 1.19.0 |
| synchronized | 3.4.0+1 | 3.5.0 |
| test_api | 0.7.9 | 0.7.12 |
| vector_math | 2.2.0 | 2.4.3 |

这是保持原 lock 文件不变的 resolved-cache debug 构建，不是原 lock 重放，不是 release。原 lock 要求 Dart≥3.12，且5个差异包受当前 Flutter SDK 精确 pin；需要兼容 SDK、缺失 lock 版本包及校验后才能证明发布重现。缓存源码 copy hash 证明复制一致，不等于上游发布 tarball 校验。APK/模拟器通过也不代表真实推送、媒体、真机或麒麟整链路已验收。

## 2026-11-04 独立模拟器安装与登录前准备

- 启动前空闲3323MiB，ADB无设备，5580/5581端口无监听；重新核对APK SHA256与上文一致。
- 仅启动本任务创建的 `wearable_cluster_1104`，serial **`emulator-5580`**，独立 `ANDROID_AVD_HOME`/`ANDROID_USER_HOME`。启动使用 `Start-Process -WindowStyle Hidden`，`-no-window -no-audio -no-snapshot -gpu software -memory 1536 -cores 2 -port 5580`；启动进程PID65084和时间保存于 `emulator-start.json`。WHPX正常，`emu avd name`确认名称，`sys.boot_completed=1`。
- `adb -s emulator-5580 install -r .../app-debug.apk`返回Success；已安装包 `com.rolling.intelligence_headband`，versionName1.3.1/versionCode8、DEBUGGABLE、x86_64，与APK读回一致。
- 屏幕1080×2280；启动activity为 `com.rolling.intelligence_headband/.MainActivity`。首次 `am start -W` 返回等待timeout（11.872秒），随后截图、UI树、窗口焦点及进程读回确认应用实际已启动并呈现登录页；没有把启动命令exit0当作页面验证。
- 登录页账户和密码均空，显示“无法读取登录状态，请重新登录”。这是实际观察，尚未诊断原因；此时后端按父任务计划停机。未输入账户、未点击登录、未授予额外权限、未访问业务页面。
- 开机后内存曾降至约969MiB，页面读回时约1.6GiB，最终记录801MiB；已通知父任务资源余量，未启动其他设备或服务。父任务随后要求保存快照并关闭，以先完成双节点/PC验收。
- 新证据：`emulator-start.json`、`emulator-stdout.log`、`emulator-stderr.log`、`adb-install.log`、`adb-launch.log`、`installed-activity.txt`、`installed-package.txt`、`screen-size.txt`、`app-pid.txt`、`foreground.txt`、`login-page.png`、`login-page.xml`、`device-prepared.json`。所有文件位于 `output/dm8-cluster/android-final/`。

后续所有设备操作显式指定serial，先读回当前页面再做坐标操作：

```powershell
$adb = 'D:/Android/Sdk/platform-tools/adb.exe'
& $adb -s emulator-5580 emu avd name
& $adb -s emulator-5580 shell wm size
& $adb -s emulator-5580 shell dumpsys window
& $adb -s emulator-5580 shell uiautomator dump /sdcard/cluster-current.xml
```

本阶段仍不构成登录、后端业务、媒体或真实推送验收；未改动原源码、lock、index或其他AVD。

### 登录前快照与停止

再次通过 `adb -s emulator-5580 emu avd name` 确认 `wearable_cluster_1104` 后，执行 `emu avd snapshot save lab-login-ready` 返回OK；快照列表确认 `lab-login-ready` 存在。快照包含空账户/密码登录页，没有输入过凭据。独立路径为 `D:/DevTools/wearable-cluster-android-1104/avd/wearable_cluster_1104.avd/snapshots/lab-login-ready`；文件大小和SHA256记录在 `snapshot-manifest.json`。快照保存日志、列表、AVD身份均留存。

保存后再次核对AVD名称，仅对 `emulator-5580` 执行 `emu kill`，收到正常退出确认；ADB设备列表为空，初始启动PID65084已不存在。未停止其他设备/服务。当前模拟器为**已关闭**，等待父任务通知才恢复。

恢复脚本 `output/dm8-cluster/android-final/resume-avd.ps1` 已准备但**尚未执行/验证恢复**，检查空闲内存至少3000MiB且专属端口空闲；设置上述两个独立Android目录，使用 `-snapshot lab-login-ready -no-snapshot-save`（不能同时传 `-no-snapshot`），隐藏headless启动。收到父任务通知后运行该脚本，再显式 `adb -s emulator-5580 emu avd name`、`shell getprop sys.boot_completed`、`shell wm size` 和截图/UI树确认恢复状态。恢复脚本不会登录或安装其他应用。

## 实际登录尝试发现的隔离构建缺陷

父任务释放内存后执行恢复脚本；AVD身份、bootCompleted、1080×2280确认一致，但恢复停在launcher而非登录页，重新打开App后页面出现。全程只操作emulator-5580。内存曾低至707MiB，随后回升约1.6GiB；没有同时启动其他重任务。

仅使用父任务正式创建的隔离人员账号，经私密文件读取、ADB shell stdin输入，未输出密码/携密参数或保存有输入内容的表单截图。第一次键盘位移导致本地“请输入密码”，改为每步重新读取EditText bounds后完成输入。有效提交先显示“无法连接服务”；本AVD WiFi默认网络只有IPv6路由，对10.0.2.2返回Network is unreachable。仅关闭该AVD WiFi，切换模拟蜂窝eth0后，10.0.2.2 ping与18080 TCP通过。再次UI提交显示“登录未完成，请稍后重试”，出现“重新验证已有会话”。未使用此按钮绕过凭据持久化。

运行日志明确：`GeneratedPluginsRegister` 无法找到 `io.flutter.plugins.GeneratedPluginRegistrant`（ClassNotFoundException）。原工程ignored文件 `android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java` 存在；ASCII副本该文件缺失。prepare_ascii.py第26行仅复制 `git ls-files --cached --others --exclude-standard`，遗漏ignored生成注册源；`flutter build apk --no-pub`没有补生成它，尽管Gradle已打包插件依赖。MainActivity正确调用 `super.configureFlutterEngine`，不是产品代码缺少注册调用。

原注册文件与ASCII `.flutter-plugins-dependencies` 22项Android插件逐一比对各自pubspec的package/pluginClass：17个原生MethodChannel注册类完全一致，5项无pluginClass（FFI等）无需注册，无额外类。见 `registrant-comparison.json`。最小修复为补复制这份已核对的原生成注册文件到ASCII副本，继续同一resolved-cache debug流程；不改产品源码、原lock或依赖版本。修复后必须检查DEX包含注册类并实际验证安全存储/登录，而非仅看build success。父已授权此范围，Gradle须等待父单独释放资源。

已清空两个输入框并断言为空，保存 `login-native-plugin-failure.png/.xml`、`plugin-registration-failure.log`，随后force-stop本App并仅关闭emulator-5580；最终ADB为空、空闲约4940MiB。未覆盖干净lab-login-ready快照，避免保存登录响应后的内存会话。当前登录、人员权限、设备状态、定位历史、告警照片、手动SOS及媒体边界均**尚未完成验收**。

### 隔离生成文件修复包（待实际登录验证）

父授权并释放Gradle资源后，仅补复制已核对的注册文件到ASCII副本（SHA256 `d7e5705f31705b9fe2ac53f993dfdc0248e5991fcde08fe85e9d7938306f71b5`），更新隔离复制脚本的显式白名单/hash门槛。未改原工程注册文件、MainActivity或任何产品源码。重建仍使用原四项defines、--no-pub、x86_64、1200m单worker，`build-debug-registrant.log` assembleDebug 187.7秒，exit0。

- 新包：`output/dm8-cluster/android-final/app-debug-registrant.apk`；226,038,947 bytes；SHA256 **`9e3b84068e61aa1b340ec8e91736d22de4af659fab4296e2e3a9a9ec06f99901`**。
- `verify-registrant-apk.py` 解析DEX header/string/type/class_defs：旧14fc包确实没有注册类；新包注册类及元数据要求的全部17个插件类定义存在，包括FlutterSecureStoragePlugin和SharedPreferencesPlugin；非仅字符串匹配。仅x86_64，实验wear地址在debug payload中。
- 633个原源码逐项hash未变，原/副本lock仍为7aa3ffece...；六项resolved差异和非release/非lock重放边界不变。新包badging仍1.3.1(8)、DEBUGGABLE；debug签名验证通过。
- 仅停止本次Gradle PID11776，精确启动时间一致；空闲约4041MiB。未启动AVD，等待父将单app-b换到最终35290a86后端，再开展安全存储持久化、登录与业务UI验收。
- 新证据：`registrant-comparison.json`、`registrant-copy.json`、`build-debug-registrant.ps1/.log`、`build-result-registrant.json`、`apk-registrant-verification.json`、`apk-registrant-badging.txt`、`apk-registrant-signature.txt`、`apk-registrant-push-metadata.txt`、`gradle-registrant-daemon.json`、`gradle-registrant-stop.json`。`android-acceptance-sequence.md`记录后续真实UI顺序与失败门槛。

## 最终后端35290a86上的真实UI第一轮

绑定后端完整SHA256 `35290a865fe8169bdaeeacab57151e379b7235a2808a4e7cbf0e8358158e8614`，APK为上述9e3b...；父确认单app-b健康且操作期间未换包。启动前3394MiB；仅恢复5580并替换安装新APK，install Success。网络沿用模拟蜂窝eth0，10.0.2.2可达；仅关闭本AVD WiFi，未动主机网络或其他设备。

|实际动作|结果与证据（output/dm8-cluster/android-final）|
|---|---|
|新包启动和原生注册|空登录页不再出现“无法读取登录状态”；FlutterSecureStorage完成非生物识别初始化/迁移，`secure-storage-runtime.log`，`registrant-first-login.png/.xml`|
|真实UI私密凭据登录|成功进入两个授权厂站选择页，再选“隔离验收-LJ”进入现场；`ui-login-result`、`ui-site-selection`、`ui-home-first`|
|force-stop→冷启动|未再输入凭据，直接恢复授权厂站选择，选LJ恢复同一人员与2装备；安全凭据持久化通过。厂站选择需重选，不能宣称所有UI状态持久化。`adb-reopen-persistence.log`、`ui-persistence-reopen`、`ui-persistence-person`|
|成员与人员绑定|我的显示隔离安卓验收人员、member、在线业务、LJ；我的装备显示对应业务人员“隔离测试人员1”、普通用户，没有提升管理员；`ui-mine-context`、`ui-my-equipment`|
|设备状态诚实|帽900000000000001、带900000000000011均离线；帽最后上报07:24:56，带06:54:33。帽详情位置“最后上报（设备离线）·坐标系未确认（原始坐标）”，接收时间提示清晰；媒体“暂无访问权限/没有可查看的媒体历史”。`ui-helmet-detail`|
|已核验事件字段|消息默认待处理0；在筛选选状态不限后，出现唯一已核验事件：人员1、帽001、06:47:32。打开详情，读取两条现场补充和核验结论“暂无法确认”、现场情况与采取措施，和父PC预期一致。`ui-events-all-status`、`ui-event-detail-top`、`ui-event-observation`|
|定位边界|事件定位明确“暂无有效定位：坐标系或定位质量未确认”，原始纬度37.456/经度118.123/UNKNOWN、设备001、06:47:31；不显示虚假的有效地图定位。此仅事件快照读回，不等于432条历史轨迹已在手机验收|
|两张实验PNG实际解码|核验区两张缩略图正常，分别点击ImageView放大；第一张人员设备页面、第二张管理设备列表页面均实际可见且内容清晰，截图`ui-event-photo-one.png`和`ui-event-photo-two.png`。不是API状态码替代视觉验收，也不是将图片中的旧在线标记当当前设备状态|

所有截图配套XML；全程未输出密码，登录输入阶段禁止截图，未向真实设备或外部媒体发送动作。登录后的账号名称作为成员上下文证据显示，不含密码/token。原生权限未额外授予；查看服务器照片不需要相机权限。

照片放大后空闲内存连续761→692MiB，按父<768MiB持续门槛暂停：保存日志/证据，确认AVD名称后force-stop本App，仅关闭emulator-5580，ADB最终为空；空闲回升约4713MiB。未保存已登录内存快照，保留原空登录lab-login-ready。`ui-acceptance-first-round.json`、`emulator-stop-memory-guard.log`记录本轮。**待续：手动SOS仅隔离账号一次创建、通讯页不可用说明、历史入口是否向member开放；均不能提前记为通过。**

## 最终短轮：合成SOS、通讯边界与可见历史

父完成隔离DM正常重启、相同数据读回和单B最终镜像健康检查后，授权同AVD以1024MiB冷启动。使用 `start-avd-shortpass.ps1`，`-no-snapshot -no-snapshot-save`，不载入或覆盖旧1536MiB快照；原userdata保留。通过设备内 `sha256sum base.apk` 确认安装包仍为9e3b完整hash；`shortpass-installed-apk-hash.txt`留存。首次身份恢复遇到WiFi IPv4不可达，关闭该AVD WiFi后eth0可达，UI“重新验证已有会话”恢复授权厂站，无需再次输入凭据。说明重启模拟器后原生凭据仍可恢复，而非仅进程内token。

- **隔离SOS真实UI创建一次**：LJ现场→手动SOS，位置 `ISOLATED LAB VALIDATION - emulator only - no real GPS`；说明 `ISOLATED LAB VALIDATION 1104 - NOT REAL EMERGENCY. Emulator test only.`。使用ASCII明确标明隔离验证/非真实求助，未填写或假造GPS。填写读回后点击提交，截图确认对话框，仅一次“确认求助”，随后自动进入新事件详情；手机发起SOS、紧急/待认领、人员“隔离测试人员1”、未关联设备仍可文字跟进，发生时间2026-11-04 08:15:51。父用已有私密API上下文按唯一说明读回恰好一条：**`SOS-448c01b6-b613-4fa5-b2e9-f80614b0896e`**，manual_sos、待认领、personId P1、version1；供后续PC故障测试。`ui-sos-final-description`、`ui-sos-confirm`、`ui-sos-created`为实际UI证据。没有重提SOS，没有通知真实设备。
- **通讯边界**：实际页面显示“当前账号未获设备语音或广播权限，可查看通讯录和事件记录”；联系人安全帽离线，设备语音/视频通话/文字播报三项均“待联调”且不可操作；没有相关通话记录。`ui-communications`截图/XML。未授权麦克风/相机，未发送呼叫、广播或真实推送；这是不可用原因验证，不是媒体能力完成。
- **历史可见范围**：成员现场页滚至底部仅设备状态/我的任务，没有人员档案或历史轨迹入口；源码 `_toolsCard`仅isAdmin展示，未深链绕过或改权限。432条定位历史未在手机UI验收。已有设备/事件最近上报与UNKNOWN坐标边界在第一轮已读回。我的装备→绑定历史弹层真实显示帽001/带011两条“当前领用”，时间06:43:14；`ui-home-lower-tools`、`ui-binding-history`。绑定历史通过不等于定位轨迹通过。
- 短轮空闲内存主要约982–1550MiB，没有触发持续<768门槛；结束确认AVD名称，force-stop本App后仅对emulator-5580执行emu kill。未保存登录态快照，未改原1536MiB配置/快照、源码或lock。`ui-acceptance-shortpass.json`、`emulator-stop-shortpass.log`记录结果。

交付使用新 `app-debug-registrant.apk`；原 `app-debug.apk`仅保留失败审计。最终边界仍为模拟器debug/实际resolved缓存，六包差异保留、非release/非原lock重放；真实硬件、生产推送、外部媒体、完整定位轨迹和麒麟实体环境仍须对应后续验收。

最终资源确认（2026-11-04T08:18:52Z）：ADB设备列表为空，本次emulator启动PID66000已退出，空闲5378MiB；`android-final-resource-state.json`和`adb-devices-final.txt`留存。`ui-evidence-manifest.json`记录56个UI截图/XML/结果文件的SHA256，便于复核。没有停止其他设备或服务。
