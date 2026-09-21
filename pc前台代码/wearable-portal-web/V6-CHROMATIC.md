# 前台彩色指挥舱（V6）

日期：2026-09-20。V5 仍发灰：同一套蓝灰提亮后层次糊在一起。本轮加深底色、按工作区上色，并用 CSS 做成 HUD 角标、登录极光和卡片 3D 倾角。

## 范围

只改 `wearable-portal-web` 外壳。Element Plus 仍管表单表格弹窗。未引入 Tailwind、Three.js、DataV npm 或第二套组件库。滚动仍由 `workspace-layout.scss` 管理。

借鉴：DataV 角标语言（自绘）、Inspira 极光思路（CSS）、Uiverse 玻璃与 3D 倾角。

## 打开

`npm run dev:mock` → http://127.0.0.1:5179  
`admin` / `Admin@2026`

对照：登录 → 安全总览（四张分色指标）→ 人员（薄荷）→ 事件（金）→ 作业（紫）。截图 `output/playwright/v6-*.png`。

## 检查脚本

`scripts/browser/v6-chromatic.js`
