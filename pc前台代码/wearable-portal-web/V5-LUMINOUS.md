# 前台深蓝指挥舱提亮（V5）

日期：2026-09-20。领导反馈不够亮、饱和度要高、要有光感。继续深蓝指挥舱，不改成白底。

## 范围

仅改 `wearable-portal-web` 视觉层。业务数据、滚动布局、后台、安卓、后端未动。没有新依赖、网络字体或循环装饰动画。

- 新增 `src/styles/v5-luminous.scss`，在 `v4-vivid.scss` 之后加载。
- 提高底色、面板、边框、主色饱和度；主按钮 / 当前导航 / 分页当前页用亮青底 + 深蓝字。
- 顶栏、导航、品牌、指标数字、主按钮加静态青光。`prefers-reduced-motion` 只关掉过渡。

## 打开

`npm run dev:mock` → http://127.0.0.1:5179  
负责人：`admin` / `Admin@2026`

建议对照：登录 → 安全总览 → 人员列表 → 现场视频 → 事件处置。截图在 `output/playwright/v5-*.png`，可与 `v4-*.png` 并排。

## 检查脚本

`scripts/browser/v5-luminous.js`
