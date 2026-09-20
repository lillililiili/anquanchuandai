# S1 验收记录

日期：2026-09-17。范围：F07/F03页面、只读API基础及隔离测试；不代表真实业务或真机验收。

## 结果

|检查|结果与证据|
|---|---|
|前端契约/适配纯逻辑|17项通过，node --test scripts/portal-contract.test.mjs|
|新增后端测试|PortalServiceTest 24项，0失败/错误/跳过；包含秒/毫秒混合精度历史排序|
|相关旧后端回归|RealDeviceModeTest 6项、PlatformDeviceSyncTest 3项全部通过；均使用Mock，不调用设备|
|S1开发浏览器|personnel.js 38项通过|
|S1生产预览浏览器|同一脚本在5177执行38项通过；请求由浏览器拦截，非真实生产API|
|原框架认证/异常回归|auth.js 32项、edge.js 11项通过，包含验证码、账号密码失败、HTTP/业务并发401、注销失败清理|
|生产资源与双工程|preview.js 5项通过，九菜单/定位刷新、无JS异常/资源404、旧PC5175与新PC5176独立运行|
|lint|通过，无错误/警告|
|build:stage / build:prod|通过，最后一次dist为生产构建；未升级依赖|
|两个目标视口|1672×941、1440×900截图复核，F07/F03无整页或正文横向溢出；较长详情通过正文滚动访问|
|真实服务有限检查|GET 127.0.0.1:18084/captchaImage返回HTTP200/code200/captchaEnabled=false；未进行登录|
|原工作区保护|原有9个tracked修改的git diff --binary与开始时一致；新代码位于原未跟踪前台、新增portal后端包及文档|

## 已覆盖的关键场景

未登录拦截、列表/独立详情登录恢复、筛选返回、人物键盘选择、四标签、人员与历史各自分页、未领用、领用未知、离线、过期、空名册、未接入名册、503及重试、历史无权限、详情404、分区失败、切厂站旧请求迟到、长姓名/设备编号、退出清会话与context。

后端额外覆盖未授权厂站、通配权限仍受厂站限制、history双权限、错误参数/重复参数、班次不确定、对象不可见、历史归属错误、迁移快照日期清空、重复设备归属、本地status不证明在线、带表领用不授权遥测。

浏览器脚本内全部网络通过测试级route拦截，出现未声明接口或设备命令即失败。业务构建没有mock入口、万能账号或自动数据回退。

## 复现命令

前台根目录：

```powershell
node --test scripts/portal-contract.test.mjs
npm run lint
npm run build:stage
npm run build:prod
npm run dev
# 另一个终端
npm run preview
```

Playwright CLI（使用已安装缓存，不加入应用依赖）：

```powershell
npx --no-install --package @playwright/cli playwright-cli -s=portal-s1 open http://localhost:5176/#/login
npx --no-install --package @playwright/cli playwright-cli -s=portal-s1 --raw run-code --filename scripts/browser/personnel.js
npx --no-install --package @playwright/cli playwright-cli -s=portal-s1 --raw run-code --filename scripts/browser/auth.js
npx --no-install --package @playwright/cli playwright-cli -s=portal-s1 --raw run-code --filename scripts/browser/edge.js
npx --no-install --package @playwright/cli playwright-cli -s=portal-s1 --raw run-code --filename scripts/browser/preview.js
npx --no-install --package @playwright/cli playwright-cli -s=portal-s1 goto http://localhost:5177/#/login
npx --no-install --package @playwright/cli playwright-cli -s=portal-s1 --raw run-code --filename scripts/browser/personnel.js
npx --no-install --package @playwright/cli playwright-cli -s=portal-s1 close
```

preview.js需要旧PC5175启动；首次冷启动若慢可等待编译就绪重跑。本次首次旧PC探测超时，待开发服务就绪后重跑通过。测试中还修正了选择器对隐藏标签的重复匹配，并修复应用筛选保留旧选择的问题，最终以通过的运行结果为准。

后端根目录：

```powershell
mvn -pl ruoyi-admin -am test '-Dtest=PortalServiceTest,RealDeviceModeTest,PlatformDeviceSyncTest' '-Dsurefire.failIfNoSpecifiedTests=false' '-DfailIfNoTests=false' -q
```

报告：后端ruoyi-admin/target/surefire-reports。截图：本工程output/playwright/s1-F07-1672.png、s1-F07-1440.png、s1-F03-1672.png、s1-F03-1440.png、s1-long-text.png。截图是合成测试数据，不能用于证明现场状态；测试输出目录不进入生产构建。

## 未验证、未实施

- 未创建真实账号，未修改任何用户权限或注册开关。
- 未部署/重启当前后端服务；新增API通过编译及独立MockMvc/服务测试，不声称已在线可用。
- MockMvc直接测试Controller、PortalAccess、Service，不含完整既有JWT/Redis安全过滤链；真实登录、跨账号/跨厂站运行验证未完成。
- 当前全局认证失败可能仍HTTP200/code401，前台兼容；新增Controller自己的错误采用HTTP与业务码一致。
- 未接入真实人员/厂站/班次/领用主数据；未建业务表或执行迁移；没有将sys_user、部门或安全帽数量假定成正式名册。
- 尚无正式设备产品图/头像授权、地图或带表协议；设备使用类型图标和文字头像，位置不虚构落点。
- 视频、对讲、广播、SOS、抓拍、录像、设备同步均未启用；厂家协议及真机验收留后续。
- 历史人员归属不完整时明确未知；当前绑定快照不作领用次数。
- 未做生产大数据量压测、完整安全审计或依赖升级。

## 接入说明

[平台实施记录](../../docs/智能穿戴设备平台/04-S1人员与装备接口基础实施记录.md)列出后端来源替换、权限边界和主数据门槛。

当前成果可以继续开发与测试，但缺账号/主数据时正式页面只显示未接入或接口未部署错误，不能提供一个“随便输入即可登录”的账号。
