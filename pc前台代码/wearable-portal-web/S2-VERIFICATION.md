# S2 验证记录

日期：2026-09-17。验收口径：页面与接口基础，不是真实业务或真机验收。

## 已执行结果

| 检查 | 结果 |
| --- | --- |
| 前端纯逻辑 | 33 项通过：S1 17 + S2 16 |
| ESLint | 通过，无警告 |
| build:stage / build:prod | 通过；最终 dist 为 production 构建 |
| 后端 PortalS2Test | 24 项通过，无失败/跳过 |
| 后端 S1 PortalServiceTest | 24 项通过 |
| 后端 RealDeviceModeTest / PlatformDeviceSyncTest | 6 + 3 项隔离回归通过，没有发送真机命令 |
| S2 浏览器开发服务 | 36 项通过 |
| S2 浏览器生产预览 | 最终 production 构建复跑 36 项通过，无资源错误 |
| S1 人员页面浏览器回归 | 38 项通过 |
| 框架认证 auth.js / edge.js | 32 + 11 项通过 |

S2 浏览器检查覆盖：登录拦截与恢复标签/厂站/选中项；地图源时间/过期/未知坐标系；轨迹手动查询、缺口、播放/暂停/停止；围栏只读；元数据与音频筛选；厂站切换；请求竞态；空结果与未接入区分；来源失败及错误码/requestId；详情失败不影响列表；无权限；401 会话清理；长文本、键盘选择；无外部底图/存储/写接口请求；无资源错误及页面异常。

纯逻辑额外验证零坐标、错误类型、长 ID、分页范围、关联证据、轨迹几何断开、安全返回地址、围栏闭合与播放卸载清理。后端测试验证七条路由、登录、各模块权限、厂站范围、不可见对象、参数与重复参数、默认未接入、来源故障、按权限用途的设备选项、历史归属、位置源时间以及 10000 点容量拒绝。

## 真实环境探测

- `http://127.0.0.1:18084/captchaImage`：HTTP 200，业务 200，captchaEnabled=false。
- 匿名请求 `/api/portal/v1/context`：HTTP 200，业务 401。仅证明现有认证链路拒绝匿名请求，**不能证明新接口已部署**。
- 未创建或使用真实账号，未验证新增权限的真实分配或真实对象范围。
- 没有重启、部署现有后端。S2 Controller/Service 在隔离 MockMvc 中执行；不含实际 JWT/Redis/数据库/设备平台完整运行链路。

## 视口与设计检查

已在 1672×941 和 1440×900 检查 F05/F06/F09/F10，页面无横向溢出；地图无虚构底图和示例落点。长列表与详情在限定区域内滚动，轨迹回放区域与片段列表分别布局。缩放/选项有标签，按钮和卡片可键盘操作，禁用操作说明原因。

截图：`output/playwright/s2-F05-1440.png`、`s2-F05-1672.png`，F06/F09/F10 同名规则；`s2-long-1440.png`、`s2-missing-1440.png`。截图全部是合成数据注入，不能证明任何真实设备在线、位置或历史归属。

按 PDF 深蓝、列表/地图/详情与资料卡片结构实施；未接入区域没有复制设计图的示例业务数据。首轮检查修正了筛选栏换行、倍速文字折行和轨迹回放可视区；当前滚动不会导致整页横向溢出。

## 复现命令

前台工程：

```powershell
node --test scripts/portal-contract.test.mjs scripts/spatial-contract.test.mjs
npm run lint
npm run build:stage
npm run build:prod
# 已有开发和预览服务时不重复启动，端口严格检查
npm run dev
npm run preview
npx --no-install --package @playwright/cli playwright-cli -s=portal-s2 open http://localhost:5176/#/login
npx --no-install --package @playwright/cli playwright-cli -s=portal-s2 --raw run-code --filename scripts/browser/spatial.js
npx --no-install --package @playwright/cli playwright-cli -s=portal-s2 goto http://localhost:5177/#/login
npx --no-install --package @playwright/cli playwright-cli -s=portal-s2 --raw run-code --filename scripts/browser/spatial.js
npx --no-install --package @playwright/cli playwright-cli -s=portal-s2 close
```

后端根目录：

```powershell
mvn -pl ruoyi-admin -am test '-Dtest=PortalS2Test,PortalServiceTest,RealDeviceModeTest,PlatformDeviceSyncTest' '-Dsurefire.failIfNoSpecifiedTests=false' '-DfailIfNoTests=false' -q
```

Surefire 报告在 ruoyi-admin/target/surefire-reports。没有运行数据库迁移或设备同步命令。浏览器脚本响应均由测试拦截提供，不加入生产包；失败后可关闭专用测试会话，避免残留拦截。

## 未验证及后续依赖

真实账号、授权厂站、人员名册、设备位置、厂家协议、历史归属、围栏真实数据、受控文件访问均未验证。底图许可、厂区配准、带表协议仍待确认。围栏写入、版本历史、事件节点、媒体预览/下载/上传/引用未实现，没有“可用演示账号”。

默认运行仍须真实登录；无数据来源显示未接入，后端未部署时可能显示接口错误，不会回退到假数据。下一次真实接入必须确认主数据和权限，再实现来源 Bean、部署后端并执行真实联调。首版来源是完整集合契约，未做生产大数据量压测；不能把上游已截断的一页声明成完整集合。

## 收尾记录

最终开发/生产 S2 隔离脚本均为 36 项通过，forbidden/errors/assets 全部为空。保留原开发与预览服务，不重启后端。测试过程中修正过 CLI 脚本运行环境的 URL 解析、导航等待和未接入夹具文案；最终结果以上述完整复跑为准，不将早期中断算作通过。
