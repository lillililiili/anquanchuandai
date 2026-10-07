# 安卓页面优化记录

日期：2026-09-11。基线：570b06d，工作树：codex/android-wearable。

本次沿用历史提示词中已确定的 CARGO 方向；在当前 Flutter 正式入口优化页面，没有恢复历史演示版或扩展延期业务。现有 Logo、安全帽图片和现场工具素材继续使用，本次未生成新图片。

## 代码变更说明

| 文件/类 | 方法/函数 | 方法作用及本次变化 |
| --- | --- | --- |
| lib/wear/queries/workbench.dart / WorkbenchPage | build、_metric、_dutyBanner、_shortcut | 待办主入口、合并统计、事件与作业前移、大字体单列；进入事件切换正确底部导航 |
| lib/wear/queries/query_widgets.dart / QueryRow | build | 独立卡片改连续列表，标题和辅助说明允许换行 |
| lib/wear/auth_pages.dart / WearLoginPage | build | 品牌图片与标题重新排版，键盘弹出隐藏装饰图片 |
| lib/wear/app.dart / WearApp | build | 统一页面标题、输入边框和焦点、按钮字重与导航样式 |
| lib/wear/ui.dart / WearCard、WearColors | build；无具体方法的颜色常量 | 卡片采用 Material 承载点击反馈，统一圆角和页面底色 |
| test/wear_app_test.dart | 新增 workbench primary action 测试 | 验证窄屏首屏按钮可点击、待认领筛选及事件导航选中状态 |

## 实际验证

- 13 项相关测试通过：wear_app_test、wear_queries_test、wear_events_widget_test。覆盖 360dp 与 1.5 倍文字、所有正式查询路由、四个主导航、登录、事件草稿恢复、键盘与防重提交。
- dart analyze lib/wear test/wear_app_test.dart：No issues found。
- git diff --check：通过。
- 按 docs/android-release.md 已有英文目录联接和 Java 临时目录配置构建成功。首次使用默认 Java 环境失败，切换项目环境后恢复；未修改构建配置。
- Android API 35 模拟器 emulator-5554，1080×2400、420dpi、文字倍率 1.0。最终 APK 覆盖安装成功，冷启动读取原登录状态。
- 实际点击：工作台主按钮→待认领事件，确认事件底部高亮；返回工作台→人员列表；返回→轨迹人员选择。检查工作台上下半屏、事件、人员与轨迹入口无可见溢出。
- 当前后端健康接口 HTTP 200。没有执行事件认领/处置等写入。
- 登录页通过组件测试，本轮未退出模拟器现有账号验证登录真机画面。真机、完整逐按钮验收和真实轨迹播放不属于本轮已通过结论。

## 体验与证据

模拟器已停留在新版工作台。APK：build/app/outputs/flutter-apk/app-debug.apk，为本机模拟器接口的 debug 联调包。

SHA-256：F21ED91172FA06F8BF65EB7F6E2B2AFCE25252EEACD59E50DE7B459C01E56B3C。

证据保存在忽略目录 build/verification/ui-20260911：preview.html、前后截图、UI XML、tests.log、analyze.log、build.log。截图不入版本库。未提交或推送 Git。

## 同日配色纠正

用户指出主题偏离原选定方案。核对原 theme/app_colors.dart 及 20260906 CARGO 交付记录后，恢复亮青 #35CFF1、海军蓝 #202B46、背景 #F6F8FC。上一轮沿用新工作树深青色并增加深色顶卡，未正确对齐旧主题，本节修正该结果。

- ui.dart / WearColors：颜色常量引用原 SpringColors；亮青用于背景强调，正文和普通图标使用海军蓝。
- app.dart / build：复用 AppTheme.lightTheme，统一按钮、选择控件、导航与输入焦点。
- workbench.dart / _dutyBanner：白色卡面、亮青按钮、海军蓝文字。
- 13 项相关回归通过，analyze 无问题，配色新版构建、覆盖安装和冷启动成功。截图确认实际工作台的按钮、导航、标题与底色符合色板。
- 本轮证据 tests-color.log、analyze-color.log、build-color.log；preview.html 更新为配色修正前后对比。其他旧截图属于配色纠正前的布局检查，不代表最终配色。
