# 告警事件改造与验证

## 已实现
- 前台“告警事件”统一帽、带、表，默认未处理；处理说明为去除首尾空白后的1—1000字，处理成功后转为已处理并记录处理人和时间。
- 删除运行中的认领、转交、核验、草稿和回执流程；保留设备、历史人员、原始告警、位置、视频、联系协助及已有资料关联。
- 使用独立 handlingStatus（UNHANDLED / HANDLED），不以旧 phase 推导设备告警处理状态；处理不会改变设备恢复状态或结束通信会话。
- 已同步概览、作业关联、人员关联、SOS提醒、统计和CSV口径。历史发生量按 occurredAt，处理量按 handledAt。
- 新详情地址 /alarms/:eventId；旧 /alarms/:eventId/verification 跳转到新详情，并清理不安全的返回地址。
- 帽含脱帽、跌落、近电、静默、SOS和独立撞击样例；带使用候选类型；表使用类型待确认样例。撞击不等于跌落，候选类型不代表厂家协议已确认。
- 真实模式经独立提供器调用原查询接口，处理状态显示未知、处理禁用；Mock写命令仅存在于Mock构建。

## 验证
- npm run test:unit：180项通过，0失败。
- npm run lint：通过。
- npm run build:mock、npm run build:prod：通过；正式产物不含 /mock-events/ 或 mock-handle-。
- scripts/browser/alarms.js：19项通过，包括三类筛选、空说明、取消离开保留输入、直接处理、只读记录、详情与返回、旧地址跳转、只读身份、空厂站、1280宽度布局。
- 浏览器页面异常0；未发送真实业务或告警处理请求。
- 单元测试覆盖并发版本冲突、幂等、身份变化/取消、跨站权限、失败不落库、历史人员未知、时间半开区间和SOS通信独立。
- 浏览器脚本通过真实页面登录和操作，不注入业务数据。取代旧 events.js、event-write.js、event-write-edge.js 告警流程脚本。其他早期阶段的交付脚本不作为本轮验收入口。

## 复查方式
先 npm run dev:mock，然后：
```powershell
New-Item -ItemType Directory -Force output/playwright/alarms | Out-Null
npx.cmd --yes --package @playwright/cli playwright-cli -s=alarm-review open http://127.0.0.1:5179
npx.cmd --yes --package @playwright/cli playwright-cli -s=alarm-review run-code --filename=scripts/browser/alarms.js
```
脚本使用仓库既有预置账号，通过登录表单切换管理员与只读用户。最后停留在只读账号的空厂站。

## 记录和边界
截图及日志：output/playwright/alarms/，含 list-1440.png、handle-1440.png、handled-1280.png、browser-result.log、unit.log、lint.log、build-mock.log、build-prod.log。
本轮仅修改PC前台；没有修改管理后台、服务端和数据库。原有地图、围栏、视觉、对讲等工作区修改保留。
数据仍为页面内存模拟，刷新恢复；未做真实设备联调，手表类型和撞击厂家协议仍待确认。
